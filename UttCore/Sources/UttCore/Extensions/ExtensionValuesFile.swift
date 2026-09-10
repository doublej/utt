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

/// What the person has said about an extension.
///
/// Three states rather than two. A manifest is a file any program on this Mac can
/// write, and the one it appears in is one utt reads three times a second — so
/// "this turned up" and "the person said yes to this" have to be different
/// answers. `pending` is the absence of a record.
public enum ExtensionConsent: String, Codable, Sendable, CaseIterable {
    /// It appeared and has not been ruled on. Inert: no jobs, no transcripts, no
    /// token, no values file.
    case pending
    /// The person said yes. Everything the manifest declares is acted on.
    case approved
    /// The person said yes once and has since switched it off.
    case disabled
}

/// Where one extension's clips go when several are waiting.
///
/// Three bands and not a number. A free integer is a ranking the person then has
/// to maintain — every new extension makes them reconsider the others — where a
/// band is a choice made once, about one extension, that stays true as the others
/// come and go.
///
/// It decides who goes next, never who is interrupted. A clip already inside the
/// engine finishes: stopping one halfway wastes the work and hands its extension
/// an error for a clip that was fine.
public enum ExtensionPriority: String, Codable, Sendable, CaseIterable {
    /// Ahead of everything waiting, however long the others have been there.
    case next
    /// Oldest first, with everything else that has not been given a band.
    case normal
    /// Behind every waiting clip that has not also been put here.
    case last

    /// The first half of the sort key. Only the order matters, and the numbers are
    /// spaced so a band could be added between two of them without renumbering.
    public var rank: Int {
        switch self {
        case .next: -10
        case .normal: 0
        case .last: 10
        }
    }

    /// What the picker says, in the person's words rather than the file's — the
    /// same bargain as `TextStage.pageName`.
    public var label: String {
        switch self {
        case .next: "First"
        case .normal: "In turn"
        case .last: "Last"
        }
    }
}

/// `<id>.consent.json` — what the person decided about this extension.
///
/// Consent is the decision it is named for, and the one it exists for: consent
/// used to be the *absence* of a `<id>.disabled` marker, which cannot tell "the
/// person approved this" from "nobody has looked at it yet", and everything an
/// extension may ask for hangs on that difference.
///
/// `priority` rides along rather than taking a file of its own. Both are facts
/// about one installed extension that have to outlive "Reset to defaults", both
/// are wanted on every `installed()` call, and one file is one read, one atomic
/// write and one thing to take to the Trash on removal. The cost is a name that
/// covers less than the file does; the keys decode independently, so an
/// unreadable priority still leaves the consent decision standing and the other
/// way round.
public struct ExtensionConsentFile: Codable, Equatable, Sendable {
    /// Never `pending` on disk: a record that exists is a decision.
    public var decision: ExtensionConsent
    /// When they said it, ISO 8601 — so a person reading the folder can see it.
    public var decidedAt: String
    /// Where this extension's clips go in the queue. Absent means `normal`, which
    /// is what every extension is until the person says otherwise.
    public var priority: ExtensionPriority

    public init(
        decision: ExtensionConsent, decidedAt: String, priority: ExtensionPriority = .normal
    ) {
        self.decision = decision
        self.decidedAt = decidedAt
        self.priority = priority
    }

    enum CodingKeys: String, CodingKey { case decision, decidedAt, priority }

    /// Forgiving in one direction only. Every other file utt reads falls back to a
    /// working default; a consent record utt cannot read falls back to `pending`,
    /// because the alternative is a truncated file granting access nobody gave.
    /// A priority it cannot read is merely `normal` — a queue position is not a
    /// grant, and refusing to run over one would be the fail-closed rule applied
    /// where nothing is at stake.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decision = (try? container.decode(ExtensionConsent.self, forKey: .decision)) ?? .pending
        decidedAt = (try? container.decode(String.self, forKey: .decidedAt)) ?? ""
        priority = (try? container.decode(ExtensionPriority.self, forKey: .priority)) ?? .normal
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

    /// What a clip gets while the extension that sent it is still waiting to be
    /// approved. An ordinary error rather than silence: an extension polling for an
    /// answer that will never come cannot otherwise tell "utt is waiting for the
    /// person" from "utt is broken", and would sit there until it timed out.
    public static let awaitingApproval =
        "utt is waiting for you to approve this extension. Open utt, go to Extensions, "
            + "approve it, and send the clip again."

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
