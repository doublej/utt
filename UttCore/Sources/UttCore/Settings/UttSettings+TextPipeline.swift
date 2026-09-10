import Dependencies
import Foundation

/// A stage of the text pipeline, so a caller can name one it does not want.
///
/// Three, because the pipeline is three decisions: what the words should be, what
/// the disfluencies around them should be, and what all of it should look like. An
/// extension sending audio is often the one caller that wants only some of them — a
/// terminal wants "claude code" spelled the way the rules spell it, and does not
/// want the whole line lowercased on the way past.
public enum TextStage: String, Codable, Sendable, CaseIterable {
    /// The user's replacement rules, the holes the deleting ones leave, and the
    /// spacing spoken punctuation leaves behind. One stage: repair and tidy exist
    /// to clean up after the rules, so running them without the rules is a no-op
    /// and skipping the rules without them leaves the debris behind.
    case replacements
    /// The on-device model taking out filler words, false starts and mid-sentence
    /// self-corrections, and putting sentence punctuation back.
    case cleanup
    /// Lowercasing and punctuation stripping.
    case formatting
}

public extension TextStage {
    /// What the settings page that owns this stage calls it, so an extension's
    /// disclosure and the page a person would go fix it use the same words.
    var pageName: String {
        switch self {
        case .replacements: "your word replacements"
        case .cleanup: "your transcript cleanup"
        case .formatting: "your text formatting"
        }
    }
}

/// The cleanup stage's model call, injected because the model lives in the app and
/// this package is pure logic.
///
/// `.skipped` covers every way cleanup can fail to happen — model unavailable, a
/// thrown `GenerationError`, or output the verifier rejected — because the answer
/// to all of them is the same: the caller keeps the raw transcript whole, never a
/// partial repair. The reason rides along rather than being logged and forgotten;
/// it is the one thing the panel, the API and an extension cannot work out for
/// themselves from the text.
public typealias TranscriptCleanup = @Sendable (String) async -> CleanupOutcome

/// A stage that can change a transcript between the recogniser and whoever
/// receives it. Not the same list as `TextStage`, which is what an extension may
/// ask to *skip*: a filter and the API's hints are stages that change the words
/// and that nothing can opt out of.
public enum TranscriptStage: String, Codable, Sendable, CaseIterable {
    case replacements
    case cleanup
    case formatting
    /// An extension that declared `filtersTranscripts` handed back other text.
    case filter
    /// The API caller's own `X-Utt-Hints` corrected a near miss. Only ever set on
    /// the API and jobs roads — a person dictating has no hints to send.
    case hints
    /// The recogniser itself. Only ever a *timing*: it produced the words rather
    /// than changing them, so it is never in `stages` — and it is where most of the
    /// time goes, so it has to be in `timings`.
    case decode
}

extension Duration {
    /// Milliseconds, to the microsecond. A number rather than a formatted string:
    /// a caller adding these up should not have to parse them first.
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        let value = Double(seconds) * 1000 + Double(attoseconds) / 1e15
        return (value * 1000).rounded() / 1000
    }
}

/// What was heard, what came out, and what happened in between.
///
/// Built once, where the pipeline runs, and threaded outward: the panel, the
/// history, an extension and an API caller all read this one object rather than
/// each reconstructing a diff of its own. Since the cleanup stage landed, the text
/// that reaches the cursor is not the text the recogniser produced, and without
/// this nothing anywhere says so.
public struct ProcessedTranscript: Equatable, Sendable {
    /// The recogniser's own output, before any stage touched it.
    public let raw: String
    /// What lands at the cursor, or goes back to the caller.
    public let text: String
    /// The stages that actually changed the words — not the ones that ran. A stage
    /// that ran and left the text alone is not worth showing anybody.
    public let stages: Set<TranscriptStage>
    /// Set when cleanup was on and did not happen. Independent of `stages`: a
    /// skipped stage changed nothing by definition.
    public let cleanupSkipped: CleanupSkipReason?
    /// How long each stretch took in milliseconds, keyed by stage name and by
    /// `decode` for the recogniser.
    ///
    /// A record parallel to `stages`, never a subset of it: a stage that ran and
    /// left the words alone took just as long, and that time is exactly what
    /// somebody chasing a slow transcription came for. Only stretches that
    /// actually ran are in it — a stage the caller skipped is absent, not zero.
    public let timings: [String: Double]

    public init(
        raw: String,
        text: String,
        stages: Set<TranscriptStage> = [],
        cleanupSkipped: CleanupSkipReason? = nil,
        timings: [String: Double] = [:]
    ) {
        self.raw = raw
        self.text = text
        self.stages = stages
        self.cleanupSkipped = cleanupSkipped
        self.timings = timings
    }

    /// True when a stage rewrote the words. Deliberately not `raw != text`: the
    /// pipeline trims, and whitespace is not something to show a person a
    /// before-and-after of.
    public var changed: Bool { !stages.isEmpty }

    /// Sorted, so the same transcript writes the same JSON twice — a `Set` would
    /// hand a watching extension a different order every time.
    public var stageNames: [String] { stages.map(\.rawValue).sorted() }

    /// The same transcript after a stage outside the settings pipeline had its
    /// turn. `raw` never moves: it is what was heard, whoever changed it since.
    ///
    /// `took` is recorded whether or not the words moved — the two are separate
    /// questions, and a filter that thought for two seconds and handed the text
    /// back unchanged spent them.
    public func applying(_ stage: TranscriptStage, text: String, took elapsed: Duration? = nil) -> Self {
        ProcessedTranscript(
            raw: raw,
            text: text,
            stages: text == self.text ? stages : stages.union([stage]),
            cleanupSkipped: cleanupSkipped,
            timings: Self.adding(elapsed, for: stage, to: timings)
        )
    }

    /// The same transcript with one more stretch measured. Adds to what that stage
    /// already spent, so two filtering extensions are one `filter` number.
    public func timed(_ stage: TranscriptStage, _ elapsed: Duration) -> Self {
        ProcessedTranscript(
            raw: raw, text: text, stages: stages, cleanupSkipped: cleanupSkipped,
            timings: Self.adding(elapsed, for: stage, to: timings)
        )
    }

    private static func adding(
        _ elapsed: Duration?, for stage: TranscriptStage, to timings: [String: Double]
    ) -> [String: Double] {
        guard let elapsed else { return timings }
        var next = timings
        next[stage.rawValue, default: 0] += elapsed.milliseconds
        return next
    }
}

/// The API's response body, and the shape every other reader was written against.
/// `text` stays exactly what it was, so a client reading only that keeps working.
extension ProcessedTranscript: Encodable {
    enum CodingKeys: String, CodingKey { case text, raw, stages, cleanupSkipped, timings }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(raw, forKey: .raw)
        try container.encode(stageNames, forKey: .stages)
        try container.encodeIfPresent(cleanupSkipped, forKey: .cleanupSkipped)
        // Absent rather than empty when nothing was measured — a transcript built
        // by hand, or by a road that does not time itself.
        if !timings.isEmpty { try container.encode(timings, forKey: .timings) }
    }
}

public extension UttSettings {
    /// Runs the raw transcript through the whole text pipeline in the one order
    /// that makes sense: apply the replacement rules in the user's order, close up
    /// the holes the deleting ones leave and the spacing spoken punctuation leaves
    /// behind, then format everything.
    ///
    /// Lives on settings rather than at each call site so the order exists in
    /// exactly one place — three appliers invoked by hand drift apart.
    ///
    /// `skipping` is for a caller that asked for a transcription rather than a
    /// person dictating: an extension declaring `skipsTextStages` gets its clip back
    /// without the stages it named. The trimming is not a stage — a transcript with
    /// leading whitespace is nobody's preference.
    func applyTextTransforms(to text: String, skipping: Set<TextStage> = []) -> String {
        let replaced = applyingReplacements(to: text, skipping: skipping)
        return applyingFormatting(to: replaced, skipping: skipping)
    }

    /// The same pipeline with the cleanup stage in it, which has to await a model,
    /// keeping a record of what each stage did to the words.
    ///
    /// Kept as a second function rather than making the one above async because
    /// `RuleBench` calls it from inside a SwiftUI view body, which cannot await.
    /// The two move together: a change to the stage order is a change to both.
    ///
    /// Cleanup sits between the replacements and the formatting deliberately. After
    /// the rules, or the model re-mangles a word the user explicitly corrected;
    /// before the formatting, or the punctuation it puts back is stripped again by
    /// `removePunctuation`. Empty input never reaches it — several spike variants
    /// answered an empty transcript with the instruction text.
    func processTranscript(
        _ raw: String,
        skipping: Set<TextStage> = [],
        cleanup: TranscriptCleanup?
    ) async -> ProcessedTranscript {
        // A monotonic clock, injected: these are durations rather than moments, and
        // a wall clock can jump backwards under one. `date.now` still stamps *when*
        // a thing happened; this measures how long it took.
        @Dependency(\.continuousClock) var clock
        var timings: [String: Double] = [:]
        var output = raw
        let replacing = clock.measure {
            output = applyingReplacements(to: raw, skipping: skipping)
        }
        if !skipping.contains(.replacements) {
            timings[TranscriptStage.replacements.rawValue] = replacing.milliseconds
        }
        var stages: Set<TranscriptStage> = output == raw ? [] : [.replacements]
        var skipped: CleanupSkipReason?
        if let cleanup, !skipping.contains(.cleanup), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Timed around both outcomes: a cleanup that gave up on the deadline
            // spent the deadline, and that is the stretch worth seeing.
            var outcome: CleanupOutcome = .skipped(.unavailable)
            let cleaning = await clock.measure { outcome = await cleanup(output) }
            timings[TranscriptStage.cleanup.rawValue] = cleaning.milliseconds
            switch outcome {
            case let .cleaned(cleaned):
                if cleaned != output { stages.insert(.cleanup) }
                output = cleaned
            case let .skipped(reason):
                skipped = reason
            }
        }
        var formatted = output
        let formatting = clock.measure {
            formatted = applyingFormatting(to: output, skipping: skipping)
        }
        if !skipping.contains(.formatting) {
            timings[TranscriptStage.formatting.rawValue] = formatting.milliseconds
        }
        // Compared against the trimmed text, because the trimming is part of that
        // call and is not a stage: leading whitespace is nobody's preference, and
        // reporting it as "your formatting changed this" would be noise.
        if formatted != output.trimmingCharacters(in: .whitespacesAndNewlines) { stages.insert(.formatting) }
        return ProcessedTranscript(
            raw: raw, text: formatted, stages: stages, cleanupSkipped: skipped, timings: timings
        )
    }

    private func applyingReplacements(to text: String, skipping: Set<TextStage>) -> String {
        guard !skipping.contains(.replacements) else { return text }
        var output = WordRemappingApplier.apply(text, remappings: wordRemappings)
        output = WordRemappingApplier.repairDeletions(output, remappings: wordRemappings)
        return WordRemappingApplier.tidySpokenPunctuation(output, remappings: wordRemappings)
    }

    private func applyingFormatting(to text: String, skipping: Set<TextStage>) -> String {
        guard !skipping.contains(.formatting) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let output = TranscriptFormattingApplier.apply(
            text,
            lowercase: lowercaseTranscripts,
            removePunctuation: removePunctuation
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
