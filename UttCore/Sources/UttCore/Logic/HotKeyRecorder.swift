import Foundation

/// Turns a stream of key events into one chosen hotkey.
///
/// The two shapes need opposite rules. A chord with a character key is finished the
/// moment that key arrives — ⌘⇧R is unambiguous. A modifier-only chord is not: while
/// ⌃ is held, the user may still be reaching for ⌥, so the choice is only final on
/// release. So this remembers the widest set it has seen and commits when the
/// modifiers let go.
public struct HotKeyRecorder {
    /// The widest modifier set seen since capture began.
    public private(set) var candidate: Modifiers = []

    public init() {}

    /// Nil means "still choosing". A non-nil result ends the capture.
    public mutating func process(_ event: KeyEvent) -> HotKey? {
        // Escape abandons the capture and leaves the old hotkey alone. Returning a
        // hotkey bound to Escape would trap the user in a shortcut they cannot undo.
        if event.key == .escape { return nil }

        if let key = event.key {
            // Sides are erased: someone recording ⌘ with their left thumb still
            // expects the right ⌘ to work.
            return HotKey(key: key, modifiers: event.modifiers.erasingSides())
        }

        let modifiers = event.modifiers.erasingSides()
        if candidate.isSubset(of: modifiers) {
            candidate = modifiers
            return nil
        }
        // Modifiers shrank: the user is letting go, so the widest set is the answer.
        guard !candidate.isEmpty else { return nil }
        return HotKey(key: nil, modifiers: candidate)
    }

    /// True once anything has been pressed, so the UI can show the chord forming.
    public var isCapturing: Bool { !candidate.isEmpty }
}
