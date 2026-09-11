import Foundation

/// A button on an extension's page.
///
/// Pressing one writes `<id>.action.json` and nothing else. utt does not run
/// programs on an extension's behalf: a manifest is a file any process on the machine
/// can write, and a manifest that could name a command to execute would turn
/// "drop a file in a folder" into "run this as the user".
public struct ExtensionAction: Codable, Hashable, Sendable, Identifiable {
    public var id: String { key }
    /// What utt writes when the button is pressed.
    public let key: String
    public let label: String
    public var detail: String?
    /// Ask first. For anything the user would not want to do by mis-clicking.
    public var confirms = false

    public init(key: String, label: String, detail: String? = nil, confirms: Bool = false) {
        self.key = key
        self.label = label
        self.detail = detail
        self.confirms = confirms
    }

    enum CodingKeys: String, CodingKey { case key, label, detail, confirms }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        detail = try? container.decodeIfPresent(String.self, forKey: .detail)
        confirms = (try? container.decodeIfPresent(Bool.self, forKey: .confirms)) as? Bool ?? false
    }

    public func sanitized() -> ExtensionAction? {
        guard ExtensionManifest.isSafeKey(key), let label = ExtensionManifest.text(label, limit: 40)
        else { return nil }
        return ExtensionAction(
            key: key,
            label: label,
            detail: ExtensionManifest.text(detail ?? "", limit: 160),
            confirms: confirms
        )
    }
}

/// A request utt has written for the extension to carry out, at `<id>.action.json`.
public struct ExtensionActionRequest: Codable, Equatable, Sendable {
    /// Increments per request. Poll it; do not act on the key alone, or pressing
    /// the same button twice looks like nothing happened.
    public var sequence: Int
    public var key: String
    public var requestedAt: String

    public init(sequence: Int, key: String, requestedAt: String) {
        self.sequence = sequence
        self.key = key
        self.requestedAt = requestedAt
    }
}

/// A launchd job utt reports the live state of.
///
/// The label only, never a path to a plist: utt asks launchd what it already
/// manages, and will not bootstrap a job on the say-so of a file that any local
/// process can write. That is the line between describing the system and changing
/// it on unverified instructions.
public struct ExtensionDaemon: Codable, Hashable, Sendable {
    public let label: String
    /// Where the daemon writes its own log. utt offers to reveal it in the Finder,
    /// which is the one thing about a dead daemon that still works — every button on
    /// an extension's page is served by the extension's own process, so when it is
    /// crash-looping the page has nothing left but Restart, and Restart is the wrong
    /// advice for a job dying on a permanent error.
    ///
    /// Revealed, never opened: `NSWorkspace.open` is LaunchServices picking an app by
    /// extension, so a manifest naming a `.command` would turn "drop a file in a
    /// folder" into "run this as the user" — the line this type already draws by
    /// taking a label rather than a plist.
    public var log: String?

    public init(label: String, log: String? = nil) {
        self.label = label
        self.log = log
    }

    /// Reverse-DNS characters only, and never Apple's own: an extension may report on
    /// its own daemon, not reach into the system's.
    public var isUsable: Bool {
        !label.isEmpty && label.count <= 128
            && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
            && !label.lowercased().hasPrefix("com.apple.")
    }

    /// The log utt will point the Finder at, or nil. An absolute path with no `..`
    /// in it: a relative one has no meaning here — utt's working directory is not
    /// the extension's — and `..` is how a bounded path stops being bounded.
    ///
    /// Existence is not checked. This is a value with no filesystem in it, and a
    /// daemon that has not written its log yet still declared where it will be.
    public var logURL: URL? {
        guard let log, log.count <= 1024, log.hasPrefix("/"), !log.hasSuffix("/"),
              !log.contains(".."), log.allSatisfy({ !$0.isNewline })
        else { return nil }
        return URL(filePath: log)
    }

    /// What `launchctl list <label>` says, as the two numbers utt reads off it.
    ///
    /// Pure so the crash case can be tested without a daemon to crash — and it needs
    /// testing: a job crash-looping on a permanent error has a pid for about a second
    /// in every ten, so whichever the poll catches is luck. The exit status is the
    /// stable half of the answer.
    public static func report(fromList output: String) -> (pid: Int?, lastExitStatus: Int?) {
        func number(_ key: String) -> Int? {
            guard let line = output.split(separator: "\n").first(where: { $0.contains("\"\(key)\"") }),
                  let raw = line.split(separator: "=").last
            else { return nil }
            return Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: " ;")))
        }
        return (number("PID"), number("LastExitStatus"))
    }
}
