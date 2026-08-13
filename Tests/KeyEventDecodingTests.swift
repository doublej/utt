import CoreGraphics
import Dependencies
import Foundation
import Testing
import UttCore
@testable import utt

@Suite("Key event decoding")
struct KeyEventDecodingTests {
    /// The contract `HotKeyProcessor` is written against: an event says what is still
    /// held. A key-up holds nothing, so it must not report the key it just released —
    /// that made a press and its release indistinguishable.
    @Test
    func aKeyUpHoldsNoKey() {
        let down = KeyEventMonitor.chord(type: .keyDown, keyCode: 35, flags: [.maskControl])
        let release = KeyEventMonitor.chord(type: .keyUp, keyCode: 35, flags: [.maskControl])

        #expect(down.key == .p)
        #expect(release.key == nil)
        #expect(release.modifiers.contains(.control))
    }

    /// `.flagsChanged` puts the modifier's own code in `keyCode`; reading it as a key
    /// would invent a keypress out of every ⌃ press.
    @Test
    func aModifierChangeHoldsNoKey() {
        let event = KeyEventMonitor.chord(type: .flagsChanged, keyCode: 59, flags: [.maskControl])

        #expect(event.key == nil)
        #expect(event.modifiers.contains(.control))
    }

    /// The reported bug, end to end: type a word, then reach for the hotkey. Typing
    /// makes the processor dirty, and only a genuinely empty chord clears it — which
    /// a key-up has to produce. Before the fix the first ⌃P was swallowed and you had
    /// to press it twice.
    @Test
    func theFirstHotkeyAfterTypingRecords() {
        withDependencies {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        } operation: {
            var processor = HotKeyProcessor(hotkey: HotKey(key: .p, modifiers: [.control]))

            for type in [CGEventType.keyDown, .keyUp] {
                _ = processor.process(
                    keyEvent: KeyEventMonitor.chord(type: type, keyCode: 0, flags: [])
                )
            }

            _ = processor.process(
                keyEvent: KeyEventMonitor.chord(
                    type: .flagsChanged, keyCode: 59, flags: [.maskControl]
                )
            )
            let output = processor.process(
                keyEvent: KeyEventMonitor.chord(type: .keyDown, keyCode: 35, flags: [.maskControl])
            )

            #expect(output == .startRecording)
        }
    }
}
