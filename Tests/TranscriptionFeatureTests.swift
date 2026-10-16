import ComposableArchitecture
import Foundation
import Testing
import UttCore
@testable import utt

/// The effect wiring, which `UttCore` cannot see because it has no clients.
///
/// The case that matters is the one utty got wrong: a discard scheduled by a
/// too-short press must not be allowed to tear down the recording that started
/// after it.
@MainActor
@Suite("TranscriptionFeature effects")
struct TranscriptionFeatureTests {
    private func makeStore(
        recording: RecordingClient = .quiet
    ) -> TestStore<TranscriptionFeature.State, TranscriptionFeature.Action> {
        TestStore(initialState: TranscriptionFeature.State()) {
            TranscriptionFeature()
        } withDependencies: {
            $0.recording = recording
            $0.transcription = .quiet
            $0.liveTranscription = .quiet
            $0.transcriptCleanup = .quiet
            $0.pasteboard = .quiet
            $0.sleepManagement = .quiet
            $0.mediaControl = .quiet
            $0.soundEffects = SoundEffectClient(play: { _, _ in })
            // The rewrite lane sits between the transcript and the paste, so every
            // transcript in here goes through it. Pass-through: what an extension does
            // to the text belongs to the filter's own tests.
            $0.extensionFilters = ExtensionFiltersClient(apply: { $0 })
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
    }

    /// The one thing the live lane must get right: the words on the panel are the
    /// preview's, and they go away the moment a real transcript exists. Two versions
    /// of the same sentence on screen is the failure this guards.
    @Test("live words fill the panel while recording and clear when the transcript lands")
    func liveWordsAppearAndClear() async {
        @Shared(.uttSettings) var settings
        $settings.withLock { $0.liveWords = true }
        defer { $settings.withLock { $0.liveWords = false } }

        let store = TestStore(initialState: TranscriptionFeature.State()) {
            TranscriptionFeature()
        } withDependencies: {
            $0.recording = .quiet
            $0.transcription = .quiet
            $0.liveTranscription = LiveTranscriptionClient(
                start: {
                    AsyncStream { continuation in
                        continuation.yield("the words")
                        continuation.yield("the words so far")
                        continuation.finish()
                    }
                },
                feed: { _ in },
                finish: {},
                isDownloaded: { true }
            )
            $0.transcriptCleanup = .quiet
            $0.pasteboard = .quiet
            $0.sleepManagement = .quiet
            $0.mediaControl = .quiet
            $0.soundEffects = SoundEffectClient(play: { _, _ in })
            $0.extensionFilters = ExtensionFiltersClient(apply: { $0 })
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.startRecording)
        await store.receive(\.liveWordsHeard) { $0.liveWords = "the words" }
        await store.receive(\.liveWordsHeard) { $0.liveWords = "the words so far" }

        // A transcript — any transcript, right or wrong — ends the preview's job.
        await store.send(.transcriptReady(.success(ProcessedTranscript(raw: "the words so far", text: "the words so far")))) {
            $0.liveWords = ""
        }
        await store.send(.cancelRecording(silent: true))
        await store.finish()
    }

    @Test("a second start cancels the first recording's pipeline")
    func startCancelsInFlightPipeline() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.startRecording) { $0.status = .recording }
        // Without `cancelInFlight` on the pipeline effect, the first start's
        // effects would still be running here and could deliver a stale
        // `.recordingFinished` into the second recording.
        await store.send(.cancelRecording(silent: true)) { $0.status = .idle }
        await store.send(.startRecording) { $0.status = .recording }
        await store.send(.stopRecording) { $0.status = .transcribing }
        await store.finish()
    }

    @Test("a discarded press never reaches transcription")
    func discardIsSilentAndTerminal() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.startRecording) { $0.status = .recording }
        await store.send(.hotKey(.discard))
        await store.receive(\.cancelRecording) { $0.status = .idle }
        await store.finish()
        #expect(store.state.lastTranscript == nil)
    }

    /// Unarmed, utt is a backend for other tools and nothing else. The hotkey and
    /// `utt://start` both end in `.startRecording`, so this is the one place that
    /// has to refuse — and refusing means the microphone is never opened at all.
    @Test("an unarmed utt never opens the microphone")
    func unarmedIgnoresStart() async {
        @Shared(.uttSettings) var settings
        $settings.withLock { $0.dictationEnabled = false }
        defer { $settings.withLock { $0.dictationEnabled = true } }

        let opened = LockIsolated(false)
        var recording = RecordingClient.quiet
        recording.start = { _ in opened.setValue(true) }
        let store = makeStore(recording: recording)

        await store.send(.startRecording)
        await store.finish()

        #expect(store.state.status == .idle)
        #expect(opened.value == false)
    }

    /// Parakeet returns an empty string for audio it cannot hear, rather than
    /// failing — so an empty result plus a quiet clip has to be reported, or the
    /// app looks like it silently did nothing.
    @Test("an empty transcript from a quiet clip surfaces as a message")
    func quietClipExplainsItself() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.recordingFinished(
            RecordingResult(url: URL(filePath: "/tmp/utt-test.wav"), duration: 1, peak: 0.01)
        )) { $0.quietWarning = true }
        // Trimming happens in the effect, with the text rules and the extension
        // filters; what reaches the reducer is what would have been pasted.
        await store.send(.transcriptReady(.success(ProcessedTranscript(raw: "", text: "")))) {
            $0.status = .failed("Nothing heard — your input level looks very low")
        }
        await store.finish()
    }

    /// The panel, the history entry and every extension read one object, so the
    /// one the reducer keeps has to be the whole thing rather than its text.
    @Test("what was heard is kept beside what was delivered")
    func deliveredTranscriptKeepsWhatWasHeard() async {
        let store = makeStore()
        store.exhaustivity = .off
        let transcript = ProcessedTranscript(
            raw: "i use claude code", text: "I use Claude Code", stages: [.replacements]
        )

        await store.send(.transcriptReady(.success(transcript)))
        await store.finish()
        #expect(store.state.lastTranscript == transcript)
        #expect(store.state.lastTranscript?.changed == true)
    }

    /// What an extension's own dictation touched: the lanes it was handed, and
    /// whether anything was pasted at the cursor.
    private final class OwnedLanes: @unchecked Sendable {
        let pasted = LockIsolated(false)
        let nothing = LockIsolated<[String]>([])
        let closed = LockIsolated<[String]>([])
    }

    private func makeOwnedStore(_ lanes: OwnedLanes) -> TestStore<TranscriptionFeature.State, TranscriptionFeature.Action> {
        let store = makeStore()
        store.dependencies.pasteboard.paste = { _, _ in lanes.pasted.setValue(true); return true }
        store.dependencies.extensions = ExtensionClient(
            installed: { [] },
            write: { _, _, _ in },
            deliver: { _, _, _ in },
            level: { owner, level, _ in if level == nil { lanes.closed.withValue { $0.append(owner) } } },
            nothing: { owner, _ in lanes.nothing.withValue { $0.append(owner) } },
            request: { _, _ in },
            setEnabled: { _, _ in },
            setPriority: { _, _ in },
            remove: { _ in },
            logEntries: { [] }
        )
        store.exhaustivity = .off
        return store
    }

    private let owner = DictationOwner(id: "opencode", name: "OpenCode")

    /// The extension draws the dictation and puts the words where they go; a paste
    /// at the cursor on top of that would land them twice. Review mode included:
    /// the extension is the review.
    @Test("an extension's own dictation is handed to it, never pasted, never held for review")
    func ownedDictationIsHandedOff() async {
        @Shared(.uttSettings) var settings
        $settings.withLock { $0.deliveryMode = .review }
        defer { $settings.withLock { $0.deliveryMode = .immediate } }
        let lanes = OwnedLanes()
        let store = makeOwnedStore(lanes)
        let transcript = ProcessedTranscript(raw: "ship it", text: "Ship it.")

        await store.send(.startOwnedRecording(owner)) {
            $0.status = .recording
            $0.owner = self.owner
        }
        await store.send(.transcriptReady(.success(transcript)))
        await store.receive(\.pasteFinished)
        await store.send(.cancelRecording(silent: true))
        await store.finish()

        #expect(store.state.lastTranscript == transcript)
        #expect(store.state.pendingReview == nil)
        #expect(store.state.lastDeliveredAt == nil)
        #expect(lanes.pasted.value == false)
        #expect(lanes.nothing.value.isEmpty)
        #expect(lanes.closed.value == ["opencode"])
    }

    /// Every dictation an extension starts ends in one write it can stop waiting on.
    @Test("an extension's own dictation that comes to nothing tells it so, once")
    func ownedDictationEndsInNothing() async {
        let lanes = OwnedLanes()
        let store = makeOwnedStore(lanes)

        await store.send(.startOwnedRecording(owner))
        await store.send(.transcriptReady(.success(ProcessedTranscript(raw: "", text: ""))))
        await store.send(.startOwnedRecording(owner))
        await store.send(.cancelRecording(silent: false))
        // Nothing in flight: a stray cancel is not the end of a dictation.
        await store.send(.cancelRecording(silent: false))
        await store.finish()

        #expect(lanes.nothing.value == ["opencode", "opencode"])
    }

    @Test("the person's own dictation clears the owner and is pasted as always")
    func ordinaryStartClearsTheOwner() async {
        let lanes = OwnedLanes()
        let store = makeOwnedStore(lanes)

        await store.send(.startOwnedRecording(owner))
        await store.send(.cancelRecording(silent: true))
        await store.send(.startRecording) { $0.owner = nil }
        await store.send(.transcriptReady(.success(ProcessedTranscript(raw: "hi", text: "Hi."))))
        await store.send(.cancelRecording(silent: true))
        await store.finish()

        #expect(lanes.pasted.value)
    }

    @Test("a failed paste says the text is still on the clipboard")
    func failedPasteIsReported() async {
        let store = makeStore()
        await store.send(.pasteFinished(false)) {
            $0.status = .failed("Could not paste — the text is on your clipboard")
        }
    }
}
