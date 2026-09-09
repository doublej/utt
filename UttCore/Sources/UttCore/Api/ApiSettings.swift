import Foundation

/// How far the transcription API is allowed to reach.
///
/// This one value is the whole security decision: the listener binds from it and
/// every accepted connection is filtered against it, so there is no second place
/// that can disagree about who is allowed in.
public enum ApiAccess: String, Codable, CaseIterable, Sendable {
    /// Loopback only. The port never appears on a network interface at all.
    case thisMac
    /// Loopback plus anything on a network this Mac is itself on.
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
        case .localNetwork: "Devices on a network this Mac is on — matched against this Mac's own interfaces, not against private-looking addresses."
        case .anywhere: "Any address that can reach the port. The token is then the only protection."
        }
    }

    /// Whether a caller at `peer` may connect. `peer` is a bare IP literal — no
    /// port; IPv6 zone ids and `::ffff:` mappings are tolerated.
    ///
    /// `localPrefixes` is what this Mac's own interfaces say its networks are, and
    /// `.localNetwork` is decided against those rather than against the private
    /// ranges — "has a private address" and "is on my network" are different
    /// questions, and answering the first one gets both halves wrong. A VPN hands
    /// out a private address for a network on the other side of the world, and a
    /// home network running IPv6 hands the phone on the same Wi-Fi a globally
    /// routable address. The first would have been let in and the second refused.
    ///
    /// An address that does not parse is refused by everything but `.anywhere`.
    public func allows(peer: String, localPrefixes: [IPPrefix]) -> Bool {
        guard let address = IPAddress(peer) else { return self == .anywhere }
        switch self {
        case .anywhere: return true
        case .thisMac: return address.isLoopback
        case .localNetwork:
            // Link-local is the same physical link by definition, and carries no
            // prefix an interface would report.
            if address.isLoopback || address.isLinkLocal { return true }
            return localPrefixes.contains { $0.contains(address) }
        }
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

/// What the listener is actually doing, as opposed to what the settings ask for.
///
/// The two come apart: a port already in use leaves the settings switched on and
/// nothing listening, and `NWListener` reports that asynchronously, long after the
/// call that started it returned.
public enum ApiServerState: Equatable, Sendable {
    case off
    case listening(port: UInt16)
    case failed(String)
}
