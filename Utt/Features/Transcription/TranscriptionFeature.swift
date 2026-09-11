import ComposableArchitecture
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "feature.transcription")

/// Owns the record → transcribe → paste pipeline.
///
/// Reducer cases stay one line and delegate to `private extension` methods — the
/// reference app's equivalent reducer reads at 150 lines inside a 670-line file,
/// which is the shape worth copying.
@Reducer
struct TranscriptionFeature {
    @ObservableState
    struct State: Equatable {
        var status: Status = .idle
        /// The last transcript that actually left, with what was heard beside it.
        var lastTranscript: ProcessedTranscript?
        /// Set when a recording came back suspiciously quiet, so the UI can say so
        /// instead of showing an empty result and looking broken.
        var quietWarning = false
        var recordingStartedAt: Date?
        var meterLevel: Float = 0
        /// What the live recogniser has heard so far, while the key is down. Cleared
        /// the moment the real transcript takes over — it is a preview, not a result.
        var liveWords = ""
        /// How long the clip behind `lastTranscript` ran, for the history entry.
        var lastDuration: TimeInterval = 0

        /// The transcript waiting on the user in `.review` mode. Non-nil is what
        /// arms Return and Escape — see `AppFeature.applySuppression`.
        var pendingReview: ProcessedTranscript?
        /// What the delivery is aimed at, captured when recording stops rather than
        /// when the paste happens: by then the panel is on screen and the user may
        /// have clicked somewhere else entirely.
        var deliveryTarget: AppIdentity?
        /// Set when a transcript actually reached an app. Drives the panel's
        /// post-delivery card, and its dismiss timer.
        var lastDeliveredAt: Date?

        var isRecording: Bool { status == .recording }
    }

    enum Status: Equatable {
        case idle
        case recording
        case transcribing
        case failed(String)
    }

    enum Action {
        /// A decision from the hotkey processor. These arrive in order, from one stream.
        case hotKey(HotKeyProcessor.Output)
        case startRecording
        case stopRecording
        case cancelRecording(silent: Bool)
        case recordingFinished(RecordingResult?)
        case transcriptReady(Result<ProcessedTranscript, Error>)
        case pasteFinished(Bool)
        case meterTicked(Float)
        case liveWordsHeard(String)
        case deliveryTargetCaptured(AppIdentity?)
        /// ⏎ on the review card.
        case reviewAccepted
        /// ⎋ on the review card.
        case reviewDiscarded
        case undoLastPaste
        case hudDismissed
        case hudTimerExpired
    }

    /// Cancelling `pipeline` on a new `.startRecording` is what stops a pending
    /// discard from tearing down a recording that has already begun. Not private:
    /// the review half of this reducer lives in its own file.
    enum CancelID { case pipeline, meter, hud, live }

    @Dependency(\.recording) var recording
    @Dependency(\.transcription) var transcription
    @Dependency(\.liveTranscription) var liveTranscription
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.sleepManagement) var sleepManagement
    @Dependency(\.mediaControl) var mediaControl
    @Dependency(\.soundEffects) var soundEffects
    @Dependency(\.extensionFilters) var extensionFilters
    @Dependency(\.transcriptCleanup) var transcriptCleanup
    @Dependency(\.date.now) var now
    /// Durations, not moments: a wall clock can jump, and this one only ever
    /// measures how long the recogniser took.
    @Dependency(\.continuousClock) var clock
    @Shared(.uttSettings) var settings

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .hotKey(output): return reduce(&state, hotKey: output)
            case .startRecording: return start(&state)
            case .stopRecording: return stop(&state)
            case let .cancelRecording(silent): return cancel(&state, silent: silent)
            case let .recordingFinished(result): return finished(&state, result)
            case let .transcriptReady(result): return transcribed(&state, result)
            case let .pasteFinished(pasted): return didPaste(&state, pasted)
            case let .meterTicked(level): state.meterLevel = level; return .none
            case let .liveWordsHeard(words): state.liveWords = words; return .none
            case let .deliveryTargetCaptured(app): state.deliveryTarget = app; return .none
            case .reviewAccepted: return acceptReview(&state)
            case .reviewDiscarded: return discardReview(&state)
            case .undoLastPaste: return undoLastPaste(&state)
            case .hudDismissed, .hudTimerExpired: return dismissHUD(&state)
            }
        }
    }
}

private extension TranscriptionFeature {
    func reduce(_ state: inout State, hotKey output: HotKeyProcessor.Output) -> Effect<Action> {
        switch output {
        case .startRecording: .send(.startRecording)
        case .stopRecording: .send(.stopRecording)
        // `.discard` is an accidental activation the user never meant to make —
        // announcing it with a chime would be the app apologising out loud.
        case .cancel: .send(.cancelRecording(silent: false))
        case .discard: .send(.cancelRecording(silent: true))
        }
    }

    func start(_ state: inout State) -> Effect<Action> {
        guard !state.isRecording else { return .none }
        state.status = .recording
        state.recordingStartedAt = now
        state.quietWarning = false
        state.liveWords = ""
        // A transcript still waiting on the user is over the moment they start
        // dictating the next one — otherwise ⏎ would paste the old one mid-sentence.
        endReview(&state)

        return .merge(
            play(.start),
            // At press rather than release: prewarming buys nothing on the median but
            // halves the cold-start tail, and this is the moment there is a person
            // still speaking to overlap the warm-up with.
            settings.cleanupTranscripts ? .run { _ in await transcriptCleanup.prewarm() } : .none,
            .run { [settings] send in
                // Order matters: silence the speakers and take the power assertion
                // before the microphone opens, or the first moment of the recording
                // contains whatever was playing.
                if settings.preventSystemSleep {
                    await sleepManagement.preventSleep("utt is recording")
                }
                if settings.muteWhileRecording { await mediaControl.mute() }
                do { try await recording.start(settings.microphonePriority) } catch {
                    await send(.transcriptReady(.failure(error)))
                }
            },
            .run { send in
                // Meter ticks at ~20 Hz; fast enough to look live, slow enough not
                // to flood the reducer while the audio thread is busy.
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(50))
                    await send(.meterTicked(recording.meterLevel()))
                }
            }
            .cancellable(id: CancelID.meter),
            settings.liveWords ? live() : .none
        )
        .cancellable(id: CancelID.pipeline, cancelInFlight: true)
    }

    /// The second recogniser, running beside the first for as long as the key is
    /// held. Its words are a preview on the panel and a line in each watching
    /// extension's file; nothing it produces reaches the cursor or the history.
    func live() -> Effect<Action> {
        .run { send in
            let partials = await liveTranscription.start()
            // One stream, one consumer — the same reason the key events have one.
            // A `Task` per tap block would let chunk 4 reach the decoder before
            // chunk 3, and the recogniser has no way to notice.
            //
            // ponytail: bufferingNewest caps the backlog at ~4s of audio. The
            // decoder runs an order of magnitude faster than realtime, so this is
            // a safety valve, not a policy.
            let (audio, sink) = AsyncStream<[Int16]>.makeStream(bufferingPolicy: .bufferingNewest(64))
            await recording.tee { sink.yield($0) }
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await chunk in audio { await liveTranscription.feed(chunk) }
                }
                group.addTask {
                    for await words in partials {
                        await send(.liveWordsHeard(words))
                        ExtensionStore.deliver(partial: words)
                    }
                }
            }
            sink.finish()
        }
        .cancellable(id: CancelID.live, cancelInFlight: true)
    }

    /// Unhooks the tap first, so no chunk arrives after the session it belonged to.
    func endLive() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.live),
            .run { _ in
                await recording.tee(nil)
                await liveTranscription.finish()
                ExtensionStore.deliver(partial: nil)
            }
        )
    }

    /// Undoes everything `start` did to the rest of the system. Deliberately
    /// unconditional and outside every cancellation ID: a settings toggle flipped
    /// mid-recording, or a cancelled pipeline, must never leave the Mac muted or
    /// awake forever.
    func releaseSystemHolds() -> Effect<Action> {
        .run { _ in
            await mediaControl.unmute()
            await sleepManagement.allowSleep()
        }
    }

    func play(_ effect: SoundEffect) -> Effect<Action> {
        guard settings.soundEffectsEnabled else { return .none }
        let volume = Float(settings.soundEffectsVolume)
        return .run { _ in soundEffects.play(effect, volume) }
    }

    func stop(_ state: inout State) -> Effect<Action> {
        guard state.isRecording else { return .none }
        state.status = .transcribing
        state.meterLevel = 0
        return .merge(
            .cancel(id: CancelID.meter),
            endLive(),
            play(.stop),
            releaseSystemHolds(),
            .run { send in await send(.deliveryTargetCaptured(pasteboard.frontmostApp())) },
            .run { send in await send(.recordingFinished(recording.stop())) }
        )
    }

    func cancel(_ state: inout State, silent: Bool) -> Effect<Action> {
        let wasRecording = state.isRecording
        state.status = .idle
        state.recordingStartedAt = nil
        state.meterLevel = 0
        state.liveWords = ""
        return .merge(
            .cancel(id: CancelID.meter),
            .cancel(id: CancelID.pipeline),
            endLive(),
            wasRecording && !silent ? play(.cancel) : .none,
            releaseSystemHolds(),
            .run { _ in await recording.cancel() }
        )
    }

    func finished(_ state: inout State, _ result: RecordingResult?) -> Effect<Action> {
        guard let result else {
            state.status = .idle
            state.recordingStartedAt = nil
            return .none
        }
        state.quietWarning = result.isSuspiciouslyQuiet
        state.lastDuration = result.duration
        let engine = settings.transcriptionEngine
        let model = ModelCatalog.resolve(id: settings.selectedModel, engine: engine).id
        let cleanup = transcriptCleanup.stage(enabled: settings.cleanupTranscripts)
        return .run { [settings, clock] send in
            let transcript: Result<ProcessedTranscript, Error> = await Result {
                // The user's own rules first, then any extension that asked to see the
                // text — so an extension rewrites what the person would have read, not
                // the raw recogniser output the rules are there to clean up. What was
                // heard rides along the whole way; nothing downstream can recover it.
                var heard = HeardTranscript(text: "", words: [])
                let decoding = try await clock.measure {
                    heard = try await transcription.transcribe(result.url, engine, model)
                }
                return await extensionFilters.apply(
                    settings.processTranscript(heard.text, cleanup: cleanup)
                        .heard(heard.words).timed(.decode, decoding)
                )
            }
            await send(.transcriptReady(transcript))
            try? FileManager.default.removeItem(at: result.url)
        }
        .cancellable(id: CancelID.pipeline, cancelInFlight: true)
    }

}
