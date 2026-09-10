import Foundation

/// A stage of the text pipeline, so a caller can name one it does not want.
///
/// Two, because the pipeline is two decisions: what the words should be, and what
/// they should look like. A plugin sending audio is often the one caller that
/// wants only one of them — a terminal wants "claude code" spelled the way the
/// rules spell it, and does not want the whole line lowercased on the way past.
public enum TextStage: String, Codable, Sendable, CaseIterable {
    /// The user's replacement rules, the holes the deleting ones leave, and the
    /// spacing spoken punctuation leaves behind. One stage: repair and tidy exist
    /// to clean up after the rules, so running them without the rules is a no-op
    /// and skipping the rules without them leaves the debris behind.
    case replacements
    /// Lowercasing and punctuation stripping.
    case formatting
}

public extension TextStage {
    /// What the settings page that owns this stage calls it, so a plugin's
    /// disclosure and the page a person would go fix it use the same words.
    var pageName: String {
        switch self {
        case .replacements: "your word replacements"
        case .formatting: "your text formatting"
        }
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
    /// person dictating: a plugin declaring `skipsTextStages` gets its clip back
    /// without the stages it named. The trimming is not a stage — a transcript with
    /// leading whitespace is nobody's preference.
    func applyTextTransforms(to text: String, skipping: Set<TextStage> = []) -> String {
        var output = text
        if !skipping.contains(.replacements) {
            output = WordRemappingApplier.apply(output, remappings: wordRemappings)
            output = WordRemappingApplier.repairDeletions(output, remappings: wordRemappings)
            output = WordRemappingApplier.tidySpokenPunctuation(output, remappings: wordRemappings)
        }
        if !skipping.contains(.formatting) {
            output = TranscriptFormattingApplier.apply(
                output,
                lowercase: lowercaseTranscripts,
                removePunctuation: removePunctuation
            )
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
