import Foundation

/// The file a plugin watches: what the user chose, and — when the plugin asked for
/// it and the API is on — the credentials for reaching utt.
///
/// It is the store, not a copy of one. utt reads it to populate the page and
/// rewrites it on every edit, which is why `revision` exists: a watcher comparing
/// mtime is comparing a timestamp with one-second granularity on some filesystems,
/// and would miss a second edit inside the same second.
public struct PluginValuesFile: Codable, Equatable, Sendable {
    /// Increments on every write utt makes. Never reused, never reset.
    public var revision: Int = 0
    public var values: [String: PluginValue] = [:]
    /// Present only while the manifest declared `needsApi` *and* the API is
    /// enabled with a token. Absent means "not available right now" — which is
    /// also what a plugin should treat a missing token as, rather than falling
    /// back to reading utt's settings file.
    public var api: PluginApiAccess?

    public init(revision: Int = 0, values: [String: PluginValue] = [:], api: PluginApiAccess? = nil) {
        self.revision = revision
        self.values = values
        self.api = api
    }

    enum CodingKeys: String, CodingKey { case revision, values, api }

    /// Forgiving, like `UttSettings`: a hand-edited or truncated file must not cost
    /// the user every setting on the page.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = (try? container.decodeIfPresent(Int.self, forKey: .revision)) as? Int ?? 0
        values = (try? container.decodeIfPresent([String: PluginValue].self, forKey: .values)) as? [String: PluginValue] ?? [:]
        api = try? container.decodeIfPresent(PluginApiAccess.self, forKey: .api)
    }

    /// The next revision of this file, given what the user just chose.
    ///
    /// `revision` is taken from what is on disk rather than from memory: a plugin
    /// that rewrote the file itself, or an app that restarted, must not send the
    /// counter backwards — a watcher would read the same number twice and skip an
    /// edit.
    public func next(values: [String: PluginValue], api: PluginApiAccess?) -> PluginValuesFile {
        PluginValuesFile(revision: revision &+ 1, values: values, api: api)
    }
}

/// How a plugin reaches utt's HTTP API.
public struct PluginApiAccess: Codable, Equatable, Sendable {
    public let token: String
    public let port: Int

    public init(token: String, port: Int) {
        self.token = token
        self.port = port
    }
}
