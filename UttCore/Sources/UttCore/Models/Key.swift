//
//  Key.swift
//  UttCore
//
//  The reference app models keys with Sauce's `Key` enum. UttCore is framework-free, so
//  a key here is nothing but a hardware keycode (the kVK_ANSI_* numbers). Turning a real
//  CGEvent or Sauce key into one of these — and back — belongs in Utt/Clients/Input/.
//

/// A hardware keycode.
///
/// `Key?` is the currency type throughout hotkey handling: `nil` means *no key is pressed*,
/// not "unknown key". A modifier-only hotkey is `HotKey(key: nil, modifiers: [.option])`.
public struct Key: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
}

// Single-letter keycode names are the point of this table.
// swiftlint:disable identifier_name

public extension Key {
    static let a = Key(rawValue: 0)
    static let s = Key(rawValue: 1)
    static let d = Key(rawValue: 2)
    static let f = Key(rawValue: 3)
    static let h = Key(rawValue: 4)
    static let g = Key(rawValue: 5)
    static let z = Key(rawValue: 6)
    static let x = Key(rawValue: 7)
    static let c = Key(rawValue: 8)
    static let v = Key(rawValue: 9)
    static let b = Key(rawValue: 11)
    static let q = Key(rawValue: 12)
    static let w = Key(rawValue: 13)
    static let e = Key(rawValue: 14)
    static let r = Key(rawValue: 15)
    static let y = Key(rawValue: 16)
    static let t = Key(rawValue: 17)
    static let o = Key(rawValue: 31)
    static let u = Key(rawValue: 32)
    static let i = Key(rawValue: 34)
    static let p = Key(rawValue: 35)
    static let l = Key(rawValue: 37)
    static let j = Key(rawValue: 38)
    static let k = Key(rawValue: 40)
    static let n = Key(rawValue: 45)
    static let m = Key(rawValue: 46)

    static let one = Key(rawValue: 18)
    static let two = Key(rawValue: 19)
    static let three = Key(rawValue: 20)
    static let four = Key(rawValue: 21)
    static let five = Key(rawValue: 23)
    static let six = Key(rawValue: 22)
    static let seven = Key(rawValue: 26)
    static let eight = Key(rawValue: 28)
    static let nine = Key(rawValue: 25)
    static let zero = Key(rawValue: 29)

    static let equal = Key(rawValue: 24)
    static let minus = Key(rawValue: 27)
    static let rightBracket = Key(rawValue: 30)
    static let leftBracket = Key(rawValue: 33)
    static let quote = Key(rawValue: 39)
    static let semicolon = Key(rawValue: 41)
    static let backslash = Key(rawValue: 42)
    static let comma = Key(rawValue: 43)
    static let slash = Key(rawValue: 44)
    static let period = Key(rawValue: 47)
    static let grave = Key(rawValue: 50)

    static let `return` = Key(rawValue: 36)
    static let tab = Key(rawValue: 48)
    static let space = Key(rawValue: 49)
    static let delete = Key(rawValue: 51)
    static let escape = Key(rawValue: 53)
    static let forwardDelete = Key(rawValue: 117)

    static let leftArrow = Key(rawValue: 123)
    static let rightArrow = Key(rawValue: 124)
    static let downArrow = Key(rawValue: 125)
    static let upArrow = Key(rawValue: 126)
}

// swiftlint:enable identifier_name

public extension Key {
    /// Symbol or label to show in the UI for this key.
    ///
    /// Unknown keycodes fall back to `"#<code>"` rather than crashing or rendering blank —
    /// the recorder can still show *something* for an exotic keyboard.
    var toString: String {
        Self.displayNames[rawValue] ?? "#\(rawValue)"
    }

    private static let displayNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "\"", 41: ";", 42: "\\",
        43: ",", 44: "/", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}
