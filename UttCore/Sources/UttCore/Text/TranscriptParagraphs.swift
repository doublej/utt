import Foundation

/// Splits a transcript into paragraphs and puts it back together again.
///
/// The cleanup stage sends each paragraph to the model on its own. Paragraph
/// structure is the user's, not the model's: sending the whole buffer collapsed
/// the breaks in the spike, silently and lossily. Splitting removes the
/// opportunity — the separators never reach the model at all — and it shortens
/// each unit, which helps both latency and the context window.
public enum TranscriptParagraphs {
    /// A blank line separates paragraphs: a whitespace run carrying two or more
    /// newlines. A single newline is a line break inside one paragraph and stays
    /// in the text handed to the model.
    ///
    /// `separators` are the runs verbatim, so `join(split(text))` is `text`. There
    /// is always exactly one fewer separator than there are parts.
    public static func split(_ text: String) -> (parts: [String], separators: [String]) {
        var parts: [String] = []
        var separators: [String] = []
        var part = ""
        var run = ""
        for character in text {
            guard !character.isWhitespace else {
                run.append(character)
                continue
            }
            if run.filter(\.isNewline).count >= 2 {
                parts.append(part)
                separators.append(run)
                part = ""
            } else {
                part += run
            }
            run = ""
            part.append(character)
        }
        // Trailing whitespace belongs to the last part rather than to a separator
        // with nothing after it — otherwise the round trip loses it.
        parts.append(part + run)
        return (parts, separators)
    }

    public static func join(_ parts: [String], separators: [String]) -> String {
        var output = parts.first ?? ""
        for (part, separator) in zip(parts.dropFirst(), separators) {
            output += separator + part
        }
        return output
    }
}
