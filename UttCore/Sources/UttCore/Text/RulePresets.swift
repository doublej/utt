import Foundation

/// A starting point for the replacement list, seeded into the user's own array so
/// every rule can be renamed, reordered, disabled or deleted afterwards.
public enum RulePresets {
    /// The punctuation people expect to be able to *say*. Multi-word phrases first:
    /// they are what the speech model emits for the stronger break, and a shorter
    /// rule must not get to them first.
    ///
    /// Fresh ids every call — these are appended to the user's array and two rules
    /// sharing an id would edit each other.
    public static var punctuation: [WordRemapping] {
        rules(
            ("new paragraph", "\\n\\n"),
            ("new line", "\\n"),
            ("open paren", "("),
            ("close paren", ")"),
            ("open quote", "\""),
            ("close quote", "\""),
            ("question mark", "?"),
            ("exclamation mark", "!"),
            ("full stop", "."),
            ("period", "."),
            ("comma", ","),
            ("colon", ":"),
            ("semicolon", ";"),
            ("dash", "—")
        )
    }

    /// Appends only what is not already there, by `match`, so pressing the button
    /// twice does not double the list — and so a rule the user rewrote keeps their
    /// version of it.
    public static func appendMissing(_ preset: [WordRemapping], to remappings: inout [WordRemapping]) {
        let existing = Set(
            remappings.map { $0.match.trimmingCharacters(in: .whitespaces).lowercased() }
        )
        remappings += preset.filter { !existing.contains($0.match) }
    }

    private static func rules(_ pairs: (said: String, written: String)...) -> [WordRemapping] {
        pairs.map { WordRemapping(match: $0.said, replacement: $0.written) }
    }
}
