import Foundation

/// A button on a plugin's page.
///
/// Pressing one writes `<id>.action.json` and nothing else. utt does not run
/// programs on a plugin's behalf: a manifest is a file any process on the machine
/// can write, and a manifest that could name a command to execute would turn
/// "drop a file in a folder" into "run this as the user".
public struct PluginAction: Codable, Hashable, Sendable, Identifiable {
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

    public func sanitized() -> PluginAction? {
        guard PluginManifest.isSafeIdentifier(key), let label = PluginManifest.text(label, limit: 40)
        else { return nil }
        return PluginAction(
            key: key,
            label: label,
            detail: PluginManifest.text(detail ?? "", limit: 160),
            confirms: confirms
        )
    }
}

/// A request utt has written for the plugin to carry out, at `<id>.action.json`.
public struct PluginActionRequest: Codable, Equatable, Sendable {
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
public struct PluginDaemon: Codable, Hashable, Sendable {
    public let label: String

    public init(label: String) { self.label = label }

    /// Reverse-DNS characters only, and never Apple's own: a plugin may report on
    /// its own daemon, not reach into the system's.
    public var isUsable: Bool {
        !label.isEmpty && label.count <= 128
            && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
            && !label.lowercased().hasPrefix("com.apple.")
    }
}
