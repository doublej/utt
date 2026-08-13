import Testing

@testable import UttCore

@Suite("HotKeyRecorder")
struct HotKeyRecorderTests {
    private func event(_ key: Key? = nil, _ modifiers: Modifiers = []) -> KeyEvent {
        KeyEvent(key: key, modifiers: modifiers)
    }

    @Test func keyChordCommitsImmediately() {
        var recorder = HotKeyRecorder()
        let result = recorder.process(event(.r, [.command, .shift]))
        #expect(result == HotKey(key: .r, modifiers: [.command, .shift]))
    }

    /// While ⌃ is held the user may still be reaching for ⌥, so nothing commits
    /// until the modifiers start letting go.
    @Test func modifierOnlyChordWaitsForRelease() {
        var recorder = HotKeyRecorder()
        #expect(recorder.process(event(nil, [.control])) == nil)
        #expect(recorder.process(event(nil, [.control, .fn])) == nil)
        #expect(recorder.process(event(nil, [])) == HotKey(key: nil, modifiers: [.control, .fn]))
    }

    /// Releasing one modifier of a chord still commits the whole chord — the widest
    /// set seen is the intent, not whatever survived the release order.
    @Test func partialReleaseCommitsTheWidestSet() {
        var recorder = HotKeyRecorder()
        _ = recorder.process(event(nil, [.control, .option]))
        #expect(recorder.process(event(nil, [.control])) == HotKey(key: nil, modifiers: [.control, .option]))
    }

    @Test func escapeAbandonsTheCapture() {
        var recorder = HotKeyRecorder()
        _ = recorder.process(event(nil, [.command]))
        #expect(recorder.process(event(.escape, [.command])) == nil)
    }

    /// A release with nothing ever pressed is the tail of the click that opened the
    /// recorder, not a chord.
    @Test func emptyReleaseCommitsNothing() {
        var recorder = HotKeyRecorder()
        #expect(recorder.process(event(nil, [])) == nil)
    }

    @Test func sidesAreErasedSoEitherKeyWorks() {
        var recorder = HotKeyRecorder()
        let leftCommand = Modifiers(modifiers: [Modifier.command.with(side: .left)])
        _ = recorder.process(event(nil, leftCommand))
        let captured = recorder.process(event(nil, []))
        #expect(captured == HotKey(key: nil, modifiers: [.command]))
    }
}
