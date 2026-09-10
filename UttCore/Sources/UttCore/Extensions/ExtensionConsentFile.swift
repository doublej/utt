//
//  ExtensionConsentFile.swift
//  UttCore
//
//  What the person decided about one installed extension: whether it may run at
//  all, and where its clips go when several are waiting. Both outlive "Reset to
//  defaults", which is why neither lives in settings.json.
//

import Foundation

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
