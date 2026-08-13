import Foundation

public extension HotKey {
    /// One glyph per key cap, in the order macOS writes shortcuts: ⌃⌥⇧⌘ then the key.
    ///
    /// Lives in UttCore because it is string composition over `Modifier.symbol` and
    /// `Key.toString`, not layout — the settings panel, the recorder hint and the
    /// menu bar all render the same array differently.
    var glyphs: [String] {
        var result = modifiers.isHyperkey ? ["✦"] : modifiers.sorted.map(\.kind.symbol)
        if let key { result.append(key.toString) }
        return result
    }

    /// One-line form for a menu item or a tooltip. Empty when nothing is bound.
    var displayString: String { glyphs.joined() }

    /// A hotkey with no modifiers *and* no key matches nothing — the recorder shows
    /// this as "not set" rather than an empty row that looks like a rendering bug.
    var isUnset: Bool { key == nil && modifiers.isEmpty }
}
