import Darwin
import Foundation

/// A parsed IP address.
///
/// Parsing goes through `inet_pton` rather than splitting on dots and colons: a
/// hand-rolled reader is where an access filter fails *open*. Splitting
/// `127.0.0.1.extra` on "." and dropping what will not convert leaves four octets
/// that read as loopback, and `fdgarbage` starts with "fd" whether or not it is an
/// address at all. `inet_pton` accepts neither, and everything it rejects is `nil`
/// here — which every scope but `.anywhere` refuses.
public struct IPAddress: Equatable, Sendable {
    public enum Family: Sendable { case version4, version6 }

    public let family: Family
    /// Network byte order: 4 bytes for IPv4, 16 for IPv6.
    public let bytes: [UInt8]

    /// `nil` for anything that is not an address. Tolerates the forms a peer
    /// actually arrives in: `[::1]` from a URL, `fe80::1%en0` with its zone, and
    /// `::ffff:127.0.0.1` — an IPv4 peer on a dual-stack socket, which is read back
    /// as the IPv4 address it is rather than treated as a strange IPv6 one.
    public init?(_ text: String) {
        var bare = text.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let zone = bare.firstIndex(of: "%") { bare = String(bare[..<zone]) }

        var version4 = in_addr()
        if inet_pton(AF_INET, bare, &version4) == 1 {
            self.family = .version4
            self.bytes = withUnsafeBytes(of: version4.s_addr) { Array($0) }
            return
        }

        var version6 = in6_addr()
        guard inet_pton(AF_INET6, bare, &version6) == 1 else { return nil }
        let all = withUnsafeBytes(of: version6) { Array($0) }
        if all.prefix(10).allSatisfy({ $0 == 0 }), all[10] == 0xFF, all[11] == 0xFF {
            self.family = .version4
            self.bytes = Array(all.suffix(4))
        } else {
            self.family = .version6
            self.bytes = all
        }
    }

    public var isLoopback: Bool {
        family == .version4 ? bytes[0] == 127 : bytes == Self.version6Loopback
    }

    /// Same physical link by definition: `169.254/16` and `fe80::/10`.
    public var isLinkLocal: Bool {
        switch family {
        case .version4: bytes[0] == 169 && bytes[1] == 254
        case .version6: bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80
        }
    }

    /// How many leading one bits, read as a netmask. `255.255.255.0` is 24.
    /// Anything with a gap in it is not a netmask and answers `nil`.
    public var prefixLength: Int? {
        var bits = 0
        var seenZero = false
        for byte in bytes {
            for shift in stride(from: 7, through: 0, by: -1) {
                let isOne = byte >> UInt8(shift) & 1 == 1
                if isOne {
                    if seenZero { return nil }
                    bits += 1
                } else {
                    seenZero = true
                }
            }
        }
        return bits
    }

    private static let version6Loopback: [UInt8] = Array(repeating: 0, count: 15) + [1]
}

/// A network this machine is on: an address and how much of it is the network part.
public struct IPPrefix: Equatable, Sendable {
    public let address: IPAddress
    public let bits: Int

    public init(address: IPAddress, bits: Int) {
        self.address = address
        self.bits = bits
    }

    /// Whether `other` is on this network. Families must match — an IPv4 peer is
    /// not inside an IPv6 prefix however the numbers line up.
    public func contains(_ other: IPAddress) -> Bool {
        guard other.family == address.family, bits >= 0, bits <= address.bytes.count * 8 else {
            return false
        }
        let wholeBytes = bits / 8
        guard address.bytes.prefix(wholeBytes) == other.bytes.prefix(wholeBytes) else { return false }
        let remainder = bits % 8
        guard remainder > 0 else { return true }
        let mask = UInt8(0xFF) << UInt8(8 - remainder)
        return address.bytes[wholeBytes] & mask == other.bytes[wholeBytes] & mask
    }
}
