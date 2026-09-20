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

    @Test("a failed paste says the text is still on the clipboard")
    func failedPasteIsReported() async {
        let store = makeStore()
        await store.send(.pasteFinished(false)) {
            $0.status = .failed("Could not paste — the text is on your clipboard")
        }
    }
}
