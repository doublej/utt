import Foundation

/// A full-screen sign an extension may ask utt to raise — "this Mac is being driven
/// from somewhere else" — over every screen while it is up.
///
/// The extension names an address and utt does the drawing, for the same reason
/// `daemon.log` is revealed by utt rather than by the daemon: the sign must come down
/// when the extension's process dies, so that process cannot be what draws it. utt
/// asks the address about every two seconds, and anything other than a clear "up"
/// — no answer, a slow one, an error, JSON it cannot read — is "down".
///
/// It is a sign, not a lock. It holds nothing, takes no input, and any input from the
/// person at the Mac takes it down at once.
public struct ExtensionCover: Codable, Hashable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }

    /// The address utt polls, or nil when it is not one it will. `http` or `https` on
    /// this Mac's loopback only: a manifest is a file any local process can write, and
    /// it must not be able to make utt poll the network every two seconds.
    public var endpoint: URL? {
        guard url.count <= 2048, let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parsed.host(percentEncoded: false)?.lowercased(),
              Self.loopbackHosts.contains(host)
        else { return nil }
        return parsed
    }

    public var isUsable: Bool { endpoint != nil }

    static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1", "[::1]"]

    /// What the sign says. Both lines are the extension's own words, bounded the way a
    /// manifest's text is — a sign nobody can read from across the room is no sign.
    public struct Sign: Equatable, Sendable {
        public let title: String
        public let detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    /// The sign one answer asks for, or nil for down.
    ///
    /// The answer's top-level `cover` decides: absent or null is down, and an object
    /// with a `title` is up. Everything else in the answer is ignored, so the address
    /// can be an endpoint the extension serves for other reasons.
    public static func sign(from data: Data) -> Sign? {
        guard let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cover = answer["cover"] as? [String: Any],
              let title = (cover["title"] as? String).flatMap({ ExtensionManifest.text($0, limit: 80) })
        else { return nil }
        let detail = (cover["detail"] as? String).flatMap { ExtensionManifest.text($0, limit: 240) }
        return Sign(title: title, detail: detail ?? "")
    }

    /// How long this Mac's own input must have been still before a sign may be shown.
    ///
    /// Once up, the same line is what takes it down: any key, click or mouse movement
    /// resets the idle time to nothing. Longer than one poll, because the extension's
    /// answer can lag the person sitting down by that much, and an "up" written just
    /// before they touched the Mac must not put the sign straight back.
    public static let settledIdle: TimeInterval = 5

    /// The sign to show, given what the extension asked for and how many seconds
    /// this Mac's input has been idle. Never shown to someone who is at the Mac.
    public static func shown(_ sign: Sign?, idle: TimeInterval) -> Sign? {
        idle >= settledIdle ? sign : nil
    }
}
