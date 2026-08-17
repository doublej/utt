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
        var lastTranscript: String?
        /// Set when a recording came back suspiciously quiet, so the UI can say so
        /// instead of showing an empty result and looking broken.
        var quietWarning = false
        var recordingStartedAt: Date?
        var meterLevel: Float = 0
        /// How long the clip behind `lastTranscript` ran, for the history entry.
        var lastDuration: TimeInterval = 0

        /// The transcript waiting on the user in `.review` mode. Non-nil is what
        /// arms Return and Escape — see `AppFeature.applySuppression`.
        var pendingReview: String?
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
        case transcriptReady(Result<String, Error>)
        case pasteFinished(Bool)
        case meterTicked(Float)
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
    enum CancelID { case pipeline, meter, hud }

    @Dependency(\.recording) var recording
    @Dependency(\.transcription) var transcription
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.sleepManagement) var sleepManagement
    @Dependency(\.mediaControl) var mediaControl
    @Dependency(\.soundEffects) var soundEffects
    @Dependency(\.date.now) var now
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
        // A transcript still waiting on the user is over the moment they start
        // dictating the next one — otherwise ⏎ would paste the old one mid-sentence.
        endReview(&state)

        return .merge(
            play(.start),
            .run { [settings] send in
                // Order matters: silence the speakers and take the power assertion
                // before the microphone opens, or the first moment of the recording
                // contains whatever was playing.
                if settings.preventSystemSleep {
                    await sleepManagement.preventSleep("utt is recording")
                }
                if settings.muteWhileRecording { await mediaControl.mute() }
                do { try await recording.start(settings.selectedMicrophoneID) } catch {
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
            .cancellable(id: CancelID.meter)
        )
        .cancellable(id: CancelID.pipeline, cancelInFlight: true)
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
        return .merge(
            .cancel(id: CancelID.meter),
            .cancel(id: CancelID.pipeline),
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
        return .run { send in
            await send(.transcriptReady(Result {
                try await transcription.transcribe(result.url, engine, model)
            }))
            try? FileManager.default.removeItem(at: result.url)
        }
        .cancellable(id: CancelID.pipeline, cancelInFlight: true)
    }

}
