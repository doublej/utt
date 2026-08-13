import Foundation

public extension UttSettings {
    /// Runs the raw transcript through the whole text pipeline in the one order
    /// that makes sense: remove fillers, then remap vocabulary (so a remapping
    /// can target a word a removal would have eaten), then format everything.
    ///
    /// Lives on settings rather than at each call site so the order exists in
    /// exactly one place — three appliers invoked by hand drift apart.
    func applyTextTransforms(to text: String) -> String {
        var output = text
        if wordRemovalsEnabled {
            output = WordRemovalApplier.apply(output, removals: wordRemovals)
        }
        output = WordRemappingApplier.apply(output, remappings: wordRemappings)
        output = TranscriptFormattingApplier.apply(
            output,
            lowercase: lowercaseTranscripts,
            removePunctuation: removePunctuation
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
