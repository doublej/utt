import Foundation

/// One filler-word pattern. `pattern` is a regex fragment — `uh+` catches
/// "uh", "uhh", "uhhhh" — matched case-insensitively at word boundaries.
public struct WordRemoval: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var pattern: String

    public init(id: UUID = UUID(), isEnabled: Bool = true, pattern: String) {
        self.id = id
        self.isEnabled = isEnabled
        self.pattern = pattern
    }
}

public enum WordRemovalApplier {
    /// Deletes every enabled pattern, then repairs the holes it left.
    /// Returns the input untouched when nothing matched, so a transcript that
    /// contains no filler is never re-spaced or re-trimmed behind the user's back.
    public static func apply(_ text: String, removals: [WordRemoval]) -> String {
        guard !text.isEmpty, !removals.isEmpty else { return text }
        var output = text
        var didChange = false

        for removal in removals where removal.isEnabled {
            let trimmed = removal.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // `\w` boundaries rather than `\b`: "thumb" must survive "um+".
            let pattern = "(?<!\\w)(?:\(trimmed))(?!\\w)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(output.startIndex..., in: output)
            let updated = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "")
            if updated != output {
                didChange = true
                output = updated
            }
        }

        return didChange ? cleanup(output) : text
    }

    /// Removing "um" from "Well, um, that's fine" leaves ", ," behind. Each rule
    /// fixes one shape of debris; order matters, spaces collapse before the
    /// punctuation rules look at what is adjacent to what.
    private static func cleanup(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: "[ \t]+([,\\.!?;:])", with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: "([,\\.!?;:])[ \t]*\\1+", with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?m)^[ \t]*[,\\.!?;:]+[ \t]*", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "[ \t]+\\n", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "\\n[ \t]+", with: "\n", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
