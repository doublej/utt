import Foundation

/// How far the transcription API is allowed to reach.
///
/// This one value is the whole security decision: the listener binds from it and
/// every accepted connection is filtered against it, so there is no second place
/// that can disagree about who is allowed in.
public enum ApiAccess: String, Codable, CaseIterable, Sendable {
    /// Loopback only. The port never appears on a network interface at all.
    case thisMac
    /// Loopback plus private and link-local peers — a phone on the same Wi-Fi.
    case localNetwork
    /// Anything that can reach the port. Needs a port forward to mean anything,
    /// and leaves the token as the only thing standing.
    case anywhere

    public var title: String {
        switch self {
        case .thisMac: "This Mac only"
        case .localNetwork: "This Mac and my local network"
        case .anywhere: "Anywhere"
        }
    }

    public var detail: String {
        switch self {
        case .thisMac: "Only programs running on this Mac can reach it."
        case .localNetwork: "Devices on your Wi-Fi or LAN can reach it too."
        case .anywhere: "Any address that can reach the port. The token is then the only protection."
        }
    }

    /// Whether a caller at `peer` is inside this scope. `peer` is a bare IP
    /// literal — no port, IPv6 zone ids and `::ffff:` mappings tolerated.
    public func allows(peer: String) -> Bool {
        switch self {
        case .anywhere: true
        case .localNetwork: IPAddressScope.of(peer) != .publicInternet
        case .thisMac: IPAddressScope.of(peer) == .loopback
        }
    }
}

/// Coarse classification of an IP literal, which is all the access filter needs.
/// Deliberately fails towards `.publicInternet`: an address this cannot parse is
/// treated as the widest thing it could be, never the narrowest.
enum IPAddressScope: Equatable {
    case loopback
    case privateNetwork
    case publicInternet

    static func of(_ address: String) -> IPAddressScope {
        let bare = normalize(address)
        return bare.contains(".") ? version4(bare) : version6(bare)
    }

    /// Strips the `[…]` brackets a URL form adds, the `%en0` zone an IPv6
    /// link-local address carries, and the `::ffff:` prefix that hides an IPv4
    /// peer inside an IPv6 socket — which is exactly how a loopback caller
    /// arrives on a dual-stack listener.
    private static func normalize(_ address: String) -> String {
        var bare = address.lowercased()
        bare = bare.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let zone = bare.firstIndex(of: "%") { bare = String(bare[..<zone]) }
        if let mapped = bare.range(of: "::ffff:") { bare = String(bare[mapped.upperBound...]) }
        return bare
    }

    private static func version4(_ address: String) -> IPAddressScope {
        let octets = address.split(separator: ".", omittingEmptySubsequences: false)
            .compactMap { UInt8($0) }
        guard octets.count == 4 else { return .publicInternet }
        switch (octets[0], octets[1]) {
        case (127, _): return .loopback
        case (10, _), (192, 168), (169, 254): return .privateNetwork
        case (172, 16...31): return .privateNetwork
        default: return .publicInternet
        }
    }

    private static func version6(_ address: String) -> IPAddressScope {
        if address == "::1" || address == "0:0:0:0:0:0:0:1" { return .loopback }
        // fc00::/7 unique-local and fe80::/10 link-local. Both are decidable from
        // the leading hex digits, so there is no need to expand the address.
        let head = address.prefix(3)
        if head.hasPrefix("fc") || head.hasPrefix("fd") { return .privateNetwork }
        if ["fe8", "fe9", "fea", "feb"].contains(String(head)) { return .privateNetwork }
        return .publicInternet
    }
}

/// The transcription API's settings, nested under `UttSettings.api` so the whole
/// feature is one readable object in the JSON file and growing it never touches
/// `UttSettings`' key list again.
public struct ApiSettings: Codable, Equatable, Sendable {
    /// Off. An app does not open a network listener on your behalf.
    public var enabled = false

    /// The safe end of the dial, so a user who flips the toggle without reading
    /// the picker has not exposed anything to the network.
    public var access: ApiAccess = .thisMac

    /// Unregistered, and far enough from the usual dev-server ports to survive a
    /// machine that is already running three of them.
    public var port = 8756

    /// Bearer token, generated when the API is first switched on. Empty means the
    /// server refuses to start: there is no unauthenticated mode.
    public var token = ""

    public init() {}

    /// Key by key, like `UttSettings` — a file from an older build, or one with a
    /// single hand-edited key, still loads.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        access = try container.decodeIfPresent(ApiAccess.self, forKey: .access) ?? access
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? port
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? token
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case access
        case port
        case token
    }

    /// What the server needs, or `nil` when it must not run. Fails closed: a
    /// hand-edited file that enables the API without a token, or with a port no
    /// socket can carry, gets no listener rather than an open one.
    public var configuration: ApiConfiguration? {
        guard enabled, !token.isEmpty, let port = UInt16(exactly: port), port > 0 else { return nil }
        return ApiConfiguration(port: port, access: access, token: token)
    }
}

/// The subset of `ApiSettings` the running server acts on. Separate from the
/// settings struct because "enabled with no token" is a state the settings can
/// hold and the server must never see.
public struct ApiConfiguration: Equatable, Sendable {
    public let port: UInt16
    public let access: ApiAccess
    public let token: String

    /// Cap on one uploaded clip: roughly thirteen minutes of 16 kHz mono wav, and
    /// the point past which a request is a memory problem rather than a recording.
    public static let maximumBodyBytes = 25 * 1024 * 1024

    public init(port: UInt16, access: ApiAccess, token: String) {
        self.port = port
        self.access = access
        self.token = token
    }
}

public enum ApiToken {
    /// 32 hex characters from the system CSPRNG — `SystemRandomNumberGenerator`,
    /// which Swift documents as cryptographically secure on Apple platforms.
    public static func generate() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    /// Constant-time comparison. A token check that returns on the first wrong
    /// byte tells an attacker how much of the prefix was right, which turns
    /// guessing 32 hex characters into guessing them one at a time.
    public static func matches(_ candidate: String, _ token: String) -> Bool {
        let offered = Array(candidate.utf8)
        let expected = Array(token.utf8)
        guard !expected.isEmpty else { return false }
        var difference: UInt8 = offered.count == expected.count ? 0 : 1
        for index in 0..<max(offered.count, expected.count) {
            let left = index < offered.count ? offered[index] : 0
            let right = index < expected.count ? expected[index] : 0
            difference |= left ^ right
        }
        return difference == 0
    }
}
