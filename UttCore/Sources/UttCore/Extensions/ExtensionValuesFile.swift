import Foundation

/// The file an extension watches: what the user chose, and — when the extension asked for
/// it and the API is on — the credentials for reaching utt.
///
/// It is the store, not a copy of one. utt reads it to populate the page and
/// rewrites it on every edit, which is why `revision` exists: a watcher comparing
/// mtime is comparing a timestamp with one-second granularity on some filesystems,
/// and would miss a second edit inside the same second.
public struct ExtensionValuesFile: Codable, Equatable, Sendable {
    /// Increments on every write utt makes. Never reused, never reset.
    public var revision: Int = 0
    public var values: [String: ExtensionValue] = [:]
    /// Present only while the manifest declared `needsApi` *and* the API is
    /// enabled with a token. Absent means "not available right now" — which is
    /// also what an extension should treat a missing token as, rather than falling
    /// back to reading utt's settings file.
    public var api: ExtensionApiAccess?

    public init(revision: Int = 0, values: [String: ExtensionValue] = [:], api: ExtensionApiAccess? = nil) {
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
        values = (try? container.decodeIfPresent([String: ExtensionValue].self, forKey: .values)) as? [String: ExtensionValue] ?? [:]
        api = try? container.decodeIfPresent(ExtensionApiAccess.self, forKey: .api)
    }

    /// The next revision of this file, given what the user just chose.
    ///
    /// `revision` is taken from what is on disk rather than from memory: an extension
    /// that rewrote the file itself, or an app that restarted, must not send the
    /// counter backwards — a watcher would read the same number twice and skip an
    /// edit.
    public func next(values: [String: ExtensionValue], api: ExtensionApiAccess?) -> ExtensionValuesFile {
        ExtensionValuesFile(revision: revision &+ 1, values: values, api: api)
    }
}

/// How an extension reaches utt's HTTP API.
public struct ExtensionApiAccess: Codable, Equatable, Sendable {
    public let token: String
    public let port: Int

    public init(token: String, port: Int) {
        self.token = token
        self.port = port
    }
}

/// A transcript handed to an extension that asked for them, written to
/// `<id>.transcript.json` as each one finishes.
///
/// The newest one only, not a log: utt already keeps the history, and a file that
/// grew forever would be a second copy of everything ever said, in a directory
/// nothing prunes. An extension that wants a log keeps its own.
public struct ExtensionTranscript: Codable, Equatable, Sendable {
    /// Increments on every transcript. The same bargain as `ExtensionValuesFile`'s
    /// revision — poll this, not the modification time.
    public var sequence: Int
    public var text: String
    /// What the recogniser heard, before utt's own stages had it. Always written:
    /// an extension cannot otherwise tell a mishearing from something a stage took
    /// out, and it has no second copy to compare against.
    public var raw: String?
    /// Which stages actually changed the words between the two, sorted. Empty means
    /// the text is exactly what was heard.
    public var stages: [String]?
    /// Why the cleanup stage did not run, when it was on and did not.
    public var cleanupSkipped: String?
    /// When it finished, ISO 8601.
    public var finishedAt: String
    /// Seconds of audio behind it.
    public var duration: Double
    /// Where the text was pasted, when it was pasted anywhere. Absent means the
    /// paste failed or the transcript came from the API, so no app received it.
    public var app: String?

    public init(
        sequence: Int,
        text: String,
        raw: String? = nil,
        stages: [String]? = nil,
        cleanupSkipped: String? = nil,
        finishedAt: String,
        duration: Double,
        app: String? = nil
    ) {
        self.sequence = sequence
        self.text = text
        self.raw = raw
        self.stages = stages
        self.cleanupSkipped = cleanupSkipped
        self.finishedAt = finishedAt
        self.duration = duration
        self.app = app
    }
}

/// The answer to one audio file an extension dropped in its jobs directory, written
/// beside it as `<name>.json`.
///
/// Exactly one of `text` and `error` is present. An extension that finds neither has
/// read the file while it was being written, which the atomic write makes
/// impossible — so treat that as a bug worth reporting rather than a state.
public struct ExtensionJobResult: Codable, Equatable, Sendable {
    public var text: String?
    /// Why it could not be transcribed, in words a person could be shown.
    public var error: String?
    /// When utt finished with it, ISO 8601.
    public var finishedAt: String

    public init(text: String? = nil, error: String? = nil, finishedAt: String) {
        self.text = text
        self.error = error
        self.finishedAt = finishedAt
    }

    /// Audio an extension may hand over. The extension is how AVFoundation picks its
    /// reader — a wav named `.m4a` fails to open however correct its bytes are —
    /// so it is the extension's declaration of the format, and the only one.
    public static let audioExtensions: Set<String> = ["wav", "m4a", "mp3", "aiff", "flac", "caf"]
}

/// One transcript put to an extension that declared `filtersTranscripts`, written to
/// `<id>.filter/<name>.in.json`. The extension answers with `<name>.out.json`.
public struct ExtensionFilterRequest: Codable, Equatable, Sendable {
    /// The transcript as it stands: the user's stages have run, and so has every
    /// filtering extension before this one.
    public var text: String
    /// What the recogniser heard, before any of that. A filter that rewrites text
    /// is entitled to know which words were spoken and which were put there.
    public var raw: String?
    /// The stages that changed the words so far, sorted.
    public var stages: [String]?
    /// Why the cleanup stage did not run, when it was on and did not.
    public var cleanupSkipped: String?

    public init(text: String, raw: String? = nil, stages: [String]? = nil, cleanupSkipped: String? = nil) {
        self.text = text
        self.raw = raw
        self.stages = stages
        self.cleanupSkipped = cleanupSkipped
    }
}

/// What the extension hands back: the text utt should use instead.
///
/// Read the way a manifest is read — another process wrote it. A reply utt
/// cannot read is not an empty transcript, it is no reply, and the text passes
/// through as it was. An empty string *is* a reply: the extension chose to drop it.
public struct ExtensionFilterReply: Codable, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    /// A reply longer than this is not a rewrite of a dictated sentence; it is a
    /// extension gone wrong, and pasting it would hang whatever it landed in.
    public static let maximumBytes = 1 << 20

    /// The replacement text, or nil when the file is not a usable reply.
    public static func text(in data: Data) -> String? {
        guard data.count <= maximumBytes,
              let reply = try? JSONDecoder().decode(ExtensionFilterReply.self, from: data)
        else { return nil }
        return reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
