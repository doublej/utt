import Foundation

/// One grammar fix the system checker proposed: the span it objects to and the
/// text it would put there.
public struct GrammarEdit: Sendable, Equatable {
    public var range: NSRange
    public var replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

/// Applies the checker's proposals to a transcript, or none of them.
///
/// Unlike cleanup, a correction may substitute a word, so `CleanupVerifier`'s
/// subsequence rule cannot hold it. The budget does the same job: a checker that
/// wants to change more than a quarter of the words has misread the transcript
/// (dictation in two languages, a name it does not know), and the answer to that is
/// the transcript as it was said, whole.
public enum GrammarCorrections {
    public static let maxChangedFraction = 0.25

    public static func apply(_ edits: [GrammarEdit], to text: String) -> String {
        let source = text as NSString
        // Back to front so an applied edit never moves the ones still waiting;
        // an edit that overlaps the one after it, or leaves the string, is dropped.
        var ordered: [GrammarEdit] = []
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            guard NSMaxRange(edit.range) <= source.length else { continue }
            if let last = ordered.last, NSMaxRange(edit.range) > last.range.location { continue }
            ordered.append(edit)
        }
        let changed = ordered.reduce(0) { $0 + words(source.substring(with: $1.range)) }
        let total = words(text)
        guard !ordered.isEmpty, total > 0, Double(changed) / Double(total) <= maxChangedFraction else { return text }
        var output = source
        for edit in ordered {
            output = output.replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        }
        return output as String
    }

    private static func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
