import Foundation

public extension UttSettings {
    /// Runs the raw transcript through the whole text pipeline in the one order
    /// that makes sense: apply the replacement rules in the user's order, close up
    /// the holes the deleting ones leave and the spacing spoken punctuation leaves
    /// behind, then format everything.
    ///
    /// Lives on settings rather than at each call site so the order exists in
    /// exactly one place — three appliers invoked by hand drift apart.
    func applyTextTransforms(to text: String) -> String {
        var output = WordRemappingApplier.apply(text, remappings: wordRemappings)
        output = WordRemappingApplier.repairDeletions(output, remappings: wordRemappings)
        output = WordRemappingApplier.tidySpokenPunctuation(output, remappings: wordRemappings)
        output = TranscriptFormattingApplier.apply(
            output,
            lowercase: lowercaseTranscripts,
            removePunctuation: removePunctuation
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
