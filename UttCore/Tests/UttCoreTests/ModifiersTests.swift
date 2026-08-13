import Foundation
import Testing
@testable import UttCore

@Suite("Modifiers")
struct ModifiersTests {
    @Test("carbon flags decode to the specific side when the device bits are set")
    func decodesSides() {
        // maskAlternate + device-dependent right option
        let right = Modifiers.from(carbonFlags: 0x0008_0000 | 0x0000_0040)
        #expect(right.side(for: .option) == .right)

        // maskCommand + device-dependent left command
        let left = Modifiers.from(carbonFlags: 0x0010_0000 | 0x0000_0008)
        #expect(left.side(for: .command) == .left)

        // General bit only — no device bit — stays side-agnostic.
        let either = Modifiers.from(carbonFlags: 0x0002_0000)
        #expect(either.side(for: .shift) == .either)

        #expect(Modifiers.from(carbonFlags: 0x0080_0000).contains(kind: .fn))
        #expect(Modifiers.from(carbonFlags: 0).isEmpty)
    }

    @Test("an .either requirement accepts a specific side, but not the reverse mismatch")
    func matchesExactly() {
        let held = Modifiers.from(carbonFlags: 0x0008_0000 | 0x0000_0040)
        #expect(held.matchesExactly([.option]))
        #expect(held.matchesExactly([Modifier.option.with(side: .right)]))
        #expect(!held.matchesExactly([Modifier.option.with(side: .left)]))
        #expect(!held.matchesExactly([.option, .shift]))
        #expect(!Modifiers.from(carbonFlags: 0x0008_0000 | 0x0002_0000).matchesExactly([.option]))
    }

    @Test("a modifier-only hotkey matches a key-less event and releases when it drops")
    func modifierOnlyHotKey() {
        let hotKey = HotKey(key: nil, modifiers: [.option])
        let pressed = KeyEvent(key: nil, modifiers: [Modifier.option.with(side: .left)])
        let released = KeyEvent(key: nil, modifiers: [])

        #expect(pressed.key == nil && pressed.modifiers.matchesExactly(hotKey.modifiers))
        #expect(!hotKey.modifiers.isSubset(of: released.modifiers))
    }

    @Test("keys round-trip through Codable as bare keycodes")
    func keyDisplayAndCoding() throws {
        #expect(Key.escape.toString == "⎋")
        #expect(Key.a.toString == "A")
        #expect(KeyboardCommand.cmdEnter.displayName == "⌘↩")

        let data = try JSONEncoder().encode(HotKey(key: .v, modifiers: [.option, .shift]))
        #expect(String(data: data, encoding: .utf8)?.contains("\"key\":9") == true)
        #expect(try JSONDecoder().decode(HotKey.self, from: data).key == .v)
    }
}
