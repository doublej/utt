import Foundation

/// Checks that a cleaned transcript only did what the cleanup stage is allowed to do.
///
/// Every permitted edit is a deletion or a punctuation change: filler words go,
/// false starts go, a self-correction resolves down to the corrected version.
/// Nothing the stage may do adds or substitutes a word, which turns "trust the
/// prompt" into something checkable — a substituted word, a translation, an
/// answer instead of a clean, and a summary all fail one of these three checks.
///
/// Deciding what to do about a failure is the caller's: it returns the raw
/// transcript whole, never a partial repair, because the model rewrites the whole
/// buffer and a diff cannot be attributed to a single edit.
public enum CleanupVerifier {
    /// How much of the input may vanish before the result reads as a summary
    /// rather than a clean. Filler removal on a heavily disfluent sentence is
    /// already a tenth of the words, so the budget has to sit well above that
    /// while still catching a paraphrase.
    public static let maximumDeletionRatio = 0.25

    public enum Failure: String, Sendable, Equatable, CaseIterable {
        /// A word was added or substituted, which no permitted edit does.
        case notASubsequence
        /// More of the input vanished than the budget allows: a summary, not a clean.
        case tooMuchDeleted
        /// Non-empty input came back empty.
        case emptyOutput
    }

    public enum Verdict: Sendable, Equatable {
        case passed
        case failed(Failure)
    }

    /// - Parameters:
    ///   - cleaned: What the model returned.
    ///   - raw: What it was given.
    public static func verify(cleaned: String, against raw: String) -> Verdict {
        if !raw.isBlank, cleaned.isBlank { return .failed(.emptyOutput) }

        let input = tokens(of: raw)
        let output = tokens(of: cleaned)
        guard isSubsequence(output, of: input) else { return .failed(.notASubsequence) }
        guard !input.isEmpty else { return .passed }

        let deleted = Double(input.count - output.count) / Double(input.count)
        return deleted > maximumDeletionRatio ? .failed(.tooMuchDeleted) : .passed
    }

    /// Lowercased, stripped of punctuation and split on whitespace, so that adding
    /// a full stop or capitalising a sentence — the two things the stage is asked
    /// to do beyond deleting — leaves the token sequence untouched.
    static func tokens(of text: String) -> [Substring] {
        TranscriptFormattingApplier
            .apply(text, lowercase: true, removePunctuation: true)
            .split(whereSeparator: \.isWhitespace)
    }

    private static func isSubsequence(_ output: [Substring], of input: [Substring]) -> Bool {
        var remaining = input[...]
        for token in output {
            guard let match = remaining.firstIndex(of: token) else { return false }
            remaining = remaining[remaining.index(after: match)...]
        }
        return true
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
