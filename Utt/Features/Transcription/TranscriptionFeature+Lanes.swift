import ComposableArchitecture
import Foundation
import UttCore

/// What a recording hands to extensions while it runs: the live words, and for a
/// dictation an extension started itself, the level and the end of it.
///
/// Split from the reducer, which owns the recording lifecycle and has no room left.
/// Internal, not `private`, because that reducer dispatches into these.
extension TranscriptionFeature {
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

    /// The level, to the extension drawing this dictation, at the meter's own 20 Hz.
    /// On the meter's cancel ID, so whatever stops the meter stops this — and the
    /// closing write goes out on the way out, however the recording ended.
    func reportLevel(to owner: DictationOwner) -> Effect<Action> {
        @Dependency(\.extensions) var extensions
        let lanes = extensions
        let model = ModelCatalog.resolve(
            id: settings.selectedModel, engine: settings.transcriptionEngine
        ).name
        return .run { _ in
            defer { lanes.level(owner.id, nil, model) }
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(50))
                lanes.level(owner.id, await recording.meterLevel(), model)
            }
        }
        .cancellable(id: CancelID.meter)
    }

    /// A dictation an extension started is handed to it, not pasted: the history
    /// and every extension's transcript file still get it, through the same
    /// `pasteFinished(true)` a paste would end in. Review does not apply — the
    /// extension is where the words go.
    func handOff(_ state: inout State, _ transcript: ProcessedTranscript) -> Effect<Action> {
        state.lastTranscript = transcript
        return .send(.pasteFinished(true))
    }

    /// The one write an extension's own dictation ends in when nothing came of it —
    /// cancelled, nothing heard, or a failed transcription — so it stops waiting.
    /// `duration` is the clip's, when there was one to transcribe.
    func endedWithNothing(_ state: State, duration: Double = 0) -> Effect<Action> {
        guard let owner = state.owner else { return .none }
        @Dependency(\.extensions) var extensions
        let lanes = extensions
        return .run { _ in lanes.nothing(owner.id, duration) }
    }
}
