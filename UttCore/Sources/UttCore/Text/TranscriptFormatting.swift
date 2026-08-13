import Foundation

/// Whole-transcript formatting: the two toggles that apply to every word.
///
/// Runs last in the text pipeline, after word removals and remappings, so a
/// remapping can still emit punctuation the user asked to keep.
public enum TranscriptFormattingApplier {
    /// - Parameters:
    ///   - lowercase: Lowercases the entire transcript.
    ///   - removePunctuation: Strips every Unicode punctuation character —
    ///     including the ones the ASR invents, like curly apostrophes and em
    ///     dashes. Deliberately does not re-space afterwards: a dash between
    ///     words leaves the two spaces that surrounded it, which is what a
    ///     dictated "a — b" should collapse to when the user types over it.
    public static func apply(
        _ text: String,
        lowercase: Bool,
        removePunctuation: Bool
    ) -> String {
        var output = lowercase ? text.lowercased() : text
        if removePunctuation {
            output = output.components(separatedBy: .punctuationCharacters).joined()
        }
        return output
    }
}
