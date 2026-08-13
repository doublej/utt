//
//  KeyEvent.swift
//  UttCore
//

/// Anything the hotkey processor reacts to.
public enum InputEvent: Equatable, Sendable {
    case keyboard(KeyEvent)
    case mouseClick
}

/// A snapshot of what is held down right now. `key == nil` means no key is pressed —
/// that is how releases arrive.
public struct KeyEvent: Equatable, Sendable {
    public let key: Key?
    public let modifiers: Modifiers

    public init(key: Key?, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// A keystroke to synthesize (auto-send), e.g. Enter, ⌘Enter, ⇧Enter.
public struct KeyboardCommand: Codable, Equatable, Sendable {
    public var key: Key?
    public var modifiers: Modifiers

    public init(key: Key?, modifiers: Modifiers = .init(modifiers: [])) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Modifier symbols followed by the key symbol, e.g. `⌘↩`.
    public var displayName: String {
        let modString = modifiers.sorted.map(\.kind.symbol).joined()
        let keyString = key?.toString ?? ""
        return modString + keyString
    }

    // MARK: - Common Presets

    public static let enter = KeyboardCommand(key: .return)
    public static let cmdEnter = KeyboardCommand(key: .return, modifiers: [.command])
    public static let shiftEnter = KeyboardCommand(key: .return, modifiers: [.shift])
}
