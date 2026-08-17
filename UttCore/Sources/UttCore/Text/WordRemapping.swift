import Foundation

/// A literal find-and-replace: "claude code" -> "Claude Code", "new line" -> "\n".
/// `match` is matched literally (escaped before use), case-insensitively, at word
/// boundaries — so it never fires inside a longer word.
///
/// An empty `replacement` deletes the match: taking a word out is not a separate
/// mechanism, it is a rule that writes nothing.
public struct WordRemapping: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var match: String
    public var replacement: String

    public init(id: UUID = UUID(), isEnabled: Bool = true, match: String, replacement: String) {
        self.id = id
        self.isEnabled = isEnabled
        self.match = match
        self.replacement = replacement
    }
}

public enum WordRemappingApplier {
    /// Applies every enabled remapping in order, so a later rule can rewrite an
    /// earlier rule's output. No cleanup pass: replacements substitute rather
    /// than delete, and squeezing whitespace here would eat a deliberate `\n`.
    /// Spacing around substituted punctuation is `tidySpokenPunctuation`'s job,
    /// one step later in the pipeline.
    public static func apply(_ text: String, remappings: [WordRemapping]) -> String {
        guard !remappings.isEmpty else { return text }
        var output = text
        for remapping in remappings where remapping.isEnabled {
            guard let pattern = pattern(for: remapping) else { continue }
            let replacement = processEscapeSequences(remapping.replacement)
            // Escape the template too, or a literal `$1` in the replacement
            // would be read as a capture-group reference.
            let escapedReplacement = NSRegularExpression.escapedTemplate(for: replacement)
            output = output.replacingOccurrences(
                of: pattern,
                with: escapedReplacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return output
    }

    /// Closes the holes a deleting rule leaves: "Well, um, that's fine" comes out of
    /// `apply` as "Well, , that's fine". Each pass fixes one shape of debris; order
    /// matters, spaces collapse before the punctuation passes look at what is
    /// adjacent to what.
    ///
    /// Runs only when some enabled rule deletes, so a vocabulary list never has its
    /// spacing squeezed — and returns the input untouched when nothing changed.
    public static func repairDeletions(_ text: String, remappings: [WordRemapping]) -> String {
        let deletes = remappings.contains {
            $0.isEnabled && $0.replacement.isEmpty && !$0.match.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard deletes else { return text }
        var output = text
        for (pattern, template) in deletionFixes {
            output = output.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let deletionFixes: [(String, String)] = [
        ("[ \\t]{2,}", " "),
        ("[ \\t]+([,\\.!?;:])", "$1"),
        ("([,\\.!?;:])[ \\t]*\\1+", "$1"),
        ("(?m)^[ \\t]*[,\\.!?;:]+[ \\t]*", ""),
        ("[ \\t]+\\n", "\n"),
        ("\\n[ \\t]+", "\n")
    ]

    /// Puts substituted punctuation where it would have been typed: "hello comma
    /// world" leaves "hello , world" after `apply`, and this closes the gap.
    /// Closing marks take the space before them, opening marks the space after, a
    /// newline both. Only whitespace moves — nothing is added or deleted.
    ///
    /// Runs only when some enabled rule replaces with punctuation, so a vocabulary
    /// list ("claude code" -> "Claude Code") never has its spacing rearranged.
    public static func tidySpokenPunctuation(
        _ text: String, remappings: [WordRemapping]
    ) -> String {
        let spoken = remappings.contains {
            $0.isEnabled && isPunctuation(processEscapeSequences($0.replacement))
        }
        guard spoken else { return text }
        var output = text
        for (pattern, template) in spacingFixes {
            output = output.replacingOccurrences(
                of: pattern, with: template, options: .regularExpression
            )
        }
        return output
    }

    /// Punctuation or whitespace only — "comma" -> ",". A replacement with a letter
    /// or a digit in it is vocabulary, not punctuation.
    private static func isPunctuation(_ replacement: String) -> Bool {
        !replacement.isEmpty && replacement.rangeOfCharacter(from: .alphanumerics) == nil
    }

    private static let spacingFixes: [(String, String)] = [
        ("[ \\t]+([,.;:!?)\\]}”’])", "$1"),
        ("([(\\[{“‘])[ \\t]+", "$1"),
        ("[ \\t]*\\n[ \\t]*", "\n")
    ]

    /// Whether this rule would fire against `text` — what the settings bench shows
    /// as a hit dot per row. Same pattern as `apply`, so a rule that lights up here
    /// is a rule that rewrites there.
    public static func matches(_ remapping: WordRemapping, in text: String) -> Bool {
        guard let pattern = pattern(for: remapping) else { return false }
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The word-boundary semantics live here and nowhere else. `\b` is wrong for a
    /// match that starts or ends on punctuation, so the boundary is spelled as
    /// "not preceded/followed by a word character". Nil for a rule with nothing
    /// to match on.
    private static func pattern(for remapping: WordRemapping) -> String? {
        let trimmed = remapping.match.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "(?<!\\w)\(NSRegularExpression.escapedPattern(for: trimmed))(?!\\w)"
    }

    /// Turns the escapes a user can type in a text field into real characters:
    /// `\n` -> newline, `\t` -> tab, `\r` -> return, `\\` -> backslash.
    /// The placeholder parks already-escaped backslashes so `\\n` stays literal.
    private static func processEscapeSequences(_ string: String) -> String {
        let placeholder = "\u{0000}"
        return string
            .replacingOccurrences(of: "\\\\", with: placeholder)
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: placeholder, with: "\\")
    }
}
