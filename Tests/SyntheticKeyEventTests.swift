import CoreGraphics
import Testing
@testable import utt

@Suite("Synthetic key event marker")
struct SyntheticKeyEventTests {
    @Test("marked paste events are distinguishable from user input")
    func marksPasteEvents() {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)!

        #expect(!SyntheticKeyEvent.isMarked(event))
        SyntheticKeyEvent.mark(event)
        #expect(SyntheticKeyEvent.isMarked(event))
    }
}
