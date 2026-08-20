import ComposableArchitecture
import Foundation
import Testing
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
            $0.pasteboard = .quiet
            $0.sleepManagement = .quiet
            $0.mediaControl = .quiet
            $0.soundEffects = SoundEffectClient(play: { _, _ in })
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
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
        await store.send(.transcriptReady(.success("   "))) {
            $0.status = .failed("Nothing heard — your input level looks very low")
        }
        await store.finish()
    }

    @Test("a failed paste says the text is still on the clipboard")
    func failedPasteIsReported() async {
        let store = makeStore()
        await store.send(.pasteFinished(false)) {
            $0.status = .failed("Could not paste — the text is on your clipboard")
        }
    }
}
