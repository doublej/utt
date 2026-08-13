import Foundation

/// A literal find-and-replace: "claude code" -> "Claude Code", "new line" -> "\n".
/// `match` is matched literally (escaped before use), case-insensitively, at word
/// boundaries — so it never fires inside a longer word.
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
    public static func apply(_ text: String, remappings: [WordRemapping]) -> String {
        guard !remappings.isEmpty else { return text }
        var output = text
        for remapping in remappings where remapping.isEnabled {
            let trimmed = remapping.match.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            let pattern = "(?<!\\w)\(escaped)(?!\\w)"
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
