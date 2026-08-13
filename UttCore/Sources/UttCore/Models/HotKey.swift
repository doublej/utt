//
//  HotKey.swift
//  UttCore
//
//  The `Modifiers` collection lives in Modifiers.swift to keep both files well under
//  the size cap.
//

/// One modifier key, optionally pinned to the left or right physical key.
public struct Modifier: Identifiable, Codable, Equatable, Hashable, Comparable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Comparable, Sendable {
        case command
        case option
        case shift
        case control
        // swiftlint:disable:next identifier_name
        case fn

        var order: Int {
            switch self {
            case .command: return 0
            case .option: return 1
            case .shift: return 2
            case .control: return 3
            case .fn: return 4
            }
        }

        public var displayName: String {
            switch self {
            case .command: return "Command"
            case .option: return "Option"
            case .shift: return "Shift"
            case .control: return "Control"
            case .fn: return "fn"
            }
        }

        public var symbol: String {
            switch self {
            case .option: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            case .control: return "⌃"
            case .fn: return "fn"
            }
        }

        /// `fn` has no left/right variant on Apple keyboards.
        public var supportsSideSelection: Bool {
            self != .fn
        }

        public static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.order < rhs.order
        }
    }

    public enum Side: String, Codable, CaseIterable, Comparable, Sendable {
        case either
        case left
        case right

        var order: Int {
            switch self {
            case .left: return 0
            case .either: return 1
            case .right: return 2
            }
        }

        public var displayName: String {
            switch self {
            case .either: return "Either"
            case .left: return "Left"
            case .right: return "Right"
            }
        }

        public static func < (lhs: Side, rhs: Side) -> Bool {
            lhs.order < rhs.order
        }
    }

    public var kind: Kind
    public var side: Side

    public var id: String { "\(kind.rawValue)-\(side.rawValue)" }

    public init(kind: Kind, side: Side = .either) {
        self.kind = kind
        self.side = side
    }

    public static let command = Modifier(kind: .command)
    public static let option = Modifier(kind: .option)
    public static let shift = Modifier(kind: .shift)
    public static let control = Modifier(kind: .control)
    // swiftlint:disable:next identifier_name
    public static let fn = Modifier(kind: .fn)

    public func with(side: Side) -> Modifier {
        Modifier(kind: kind, side: side)
    }

    public static func < (lhs: Modifier, rhs: Modifier) -> Bool {
        if lhs.kind == rhs.kind {
            return lhs.side.order < rhs.side.order
        }
        return lhs.kind.order < rhs.kind.order
    }

    public var stringValue: String {
        kind.symbol
    }

    /// Same kind, and the sides are compatible — `.either` matches both physical keys.
    func matches(_ other: Modifier) -> Bool {
        guard kind == other.kind else { return false }
        if side == .either || other.side == .either { return true }
        return side == other.side
    }
}

/// A key plus its modifiers.
///
/// `key == nil` means *no key* — a modifier-only hotkey such as
/// `HotKey(key: nil, modifiers: [.option])`. Press, release and "is this chord still held"
/// all fall out of comparing a `KeyEvent` against this, so there is no separate
/// release representation.
public struct HotKey: Codable, Equatable, Sendable {
    public var key: Key?
    public var modifiers: Modifiers

    public init(key: Key?, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}
