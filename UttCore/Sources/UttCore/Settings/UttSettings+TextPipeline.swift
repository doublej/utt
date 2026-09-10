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
/// Returns `nil` for every way cleanup can fail to happen — model unavailable, a
/// thrown `GenerationError`, or output the verifier rejected — because the answer
/// is the same in all of them: the caller keeps the raw transcript whole, never a
/// partial repair. Naming the reason is the closure's own business; by the time it
/// returns there is nothing left to decide here.
public typealias TranscriptCleanup = @Sendable (String) async -> String?

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

    /// The same pipeline with the cleanup stage in it, which has to await a model.
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
    func applyTextTransforms(
        to text: String,
        skipping: Set<TextStage> = [],
        cleanup: TranscriptCleanup?
    ) async -> String {
        var output = applyingReplacements(to: text, skipping: skipping)
        if let cleanup, !skipping.contains(.cleanup), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output = await cleanup(output) ?? output
        }
        return applyingFormatting(to: output, skipping: skipping)
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
