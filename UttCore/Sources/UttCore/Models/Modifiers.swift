//
//  Modifiers.swift
//  UttCore
//
//  Split out of HotKey.swift. The reference app decoded `NSEvent.ModifierFlags` and
//  `CGEventFlags` here; UttCore takes the raw `UInt64` flag word instead so no framework
//  leaks into core.
//

/// The set of modifiers held down, or the set a hotkey requires.
public struct Modifiers: Codable, Equatable, ExpressibleByArrayLiteral, Sendable {
    var modifiers: Set<Modifier>

    /// Display order. A full hyperkey renders as its own symbol, so this returns nothing.
    public var sorted: [Modifier] {
        if isHyperkey {
            return []
        }
        return modifiers.sorted()
    }

    public var isHyperkey: Bool {
        contains(kind: .command)
            && contains(kind: .option)
            && contains(kind: .shift)
            && contains(kind: .control)
    }

    public var isEmpty: Bool {
        modifiers.isEmpty
    }

    public init(modifiers: Set<Modifier>) {
        self.modifiers = modifiers
    }

    public init(arrayLiteral elements: Modifier...) {
        modifiers = Set(elements)
    }

    public func contains(_ modifier: Modifier) -> Bool {
        modifiers.contains(where: { $0.matches(modifier) })
    }

    public func contains(kind: Modifier.Kind) -> Bool {
        modifiers.contains(where: { $0.kind == kind })
    }

    public var kinds: [Modifier.Kind] {
        Array(Set(modifiers.map { $0.kind })).sorted()
    }

    public func isSubset(of other: Modifiers) -> Bool {
        modifiers.allSatisfy { other.contains($0) }
    }

    public func isDisjoint(with other: Modifiers) -> Bool {
        modifiers.allSatisfy { !other.contains($0) }
    }

    public func union(_ other: Modifiers) -> Modifiers {
        Modifiers(modifiers: modifiers.union(other.modifiers))
    }

    public func intersection(_ other: Modifiers) -> Modifiers {
        Modifiers(modifiers: modifiers.intersection(other.modifiers))
    }

    /// Every required modifier is held, and nothing else is.
    public func matchesExactly(_ expected: Modifiers) -> Bool {
        guard expected.modifiers.allSatisfy({ self.contains($0) }) else {
            return false
        }

        let allowedKinds = Set(expected.modifiers.map { $0.kind })

        return modifiers.allSatisfy { candidate in
            guard allowedKinds.contains(candidate.kind),
                  let requirement = expected.modifiers.first(where: { $0.kind == candidate.kind })
            else {
                return false
            }
            return candidate.matches(requirement)
        }
    }

    public func side(for kind: Modifier.Kind) -> Modifier.Side? {
        modifiers.first(where: { $0.kind == kind })?.side
    }

    public func setting(kind: Modifier.Kind, to side: Modifier.Side) -> Modifiers {
        var updated = modifiers.filter { $0.kind != kind }
        updated.insert(Modifier(kind: kind, side: side))
        return Modifiers(modifiers: updated)
    }

    public func erasingSides() -> Modifiers {
        Modifiers(modifiers: Set(modifiers.map { Modifier(kind: $0.kind, side: .either) }))
    }

    public func removing(kind: Modifier.Kind) -> Modifiers {
        Modifiers(modifiers: modifiers.filter { $0.kind != kind })
    }

    /// Decodes a Core Graphics event flag word (`CGEventFlags.rawValue`).
    ///
    /// The device-specific left/right bits win when present, so `⌘` on the right-hand key
    /// decodes as `.command(.right)`; otherwise the general bit yields `.either`.
    public static func from(carbonFlags: UInt64) -> Modifiers {
        var modifiers: Set<Modifier> = []

        for spec in DeviceModifierMask.specs {
            insert(spec, flags: carbonFlags, into: &modifiers)
        }

        if carbonFlags & DeviceModifierMask.secondaryFn != 0 {
            modifiers.insert(.fn)
        }

        return .init(modifiers: modifiers)
    }

    private static func insert(
        _ spec: DeviceModifierMask.Spec,
        flags: UInt64,
        into modifiers: inout Set<Modifier>
    ) {
        var insertedSpecific = false
        if flags & spec.left != 0 {
            modifiers.insert(Modifier(kind: spec.kind, side: .left))
            insertedSpecific = true
        }
        if flags & spec.right != 0 {
            modifiers.insert(Modifier(kind: spec.kind, side: .right))
            insertedSpecific = true
        }
        if !insertedSpecific, flags & spec.general != 0 {
            modifiers.insert(Modifier(kind: spec.kind, side: .either))
        }
    }
}

/// Raw `CGEventFlags` bits — the general masks plus the undocumented-but-stable
/// device-dependent left/right bits.
private enum DeviceModifierMask {
    struct Spec {
        let kind: Modifier.Kind
        let general: UInt64
        let left: UInt64
        let right: UInt64
    }

    static let secondaryFn: UInt64 = 0x0080_0000

    static let specs: [Spec] = [
        Spec(kind: .shift, general: 0x0002_0000, left: 0x0000_0002, right: 0x0000_0004),
        Spec(kind: .control, general: 0x0004_0000, left: 0x0000_0001, right: 0x0000_2000),
        Spec(kind: .option, general: 0x0008_0000, left: 0x0000_0020, right: 0x0000_0040),
        Spec(kind: .command, general: 0x0010_0000, left: 0x0000_0008, right: 0x0000_0010)
    ]
}
