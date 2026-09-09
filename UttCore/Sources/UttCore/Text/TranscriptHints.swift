import Foundation

/// Corrects a transcript against words the caller knew were coming.
///
/// A recogniser hears sound and guesses words; a caller often knows the vocabulary
/// before it sends the clip — the repo being worked in, the session's name, the
/// product's own name. Nothing connected those two facts, so the terms carrying the
/// meaning were the ones that came back wrong: "cockwheel" for cogwheel, "Tu Y"
/// for TUI, "deck uh deck hand" for deckhand — that last one in a clip about
/// deckhand, sent by deckhand.
///
/// Deliberately conservative. A wrong correction is worse than a missed one,
/// because it is invisible: the sentence still reads, it just says something else.
/// So a hint only displaces text that is already nearly it, never merely similar.
public enum TranscriptHints {
    /// How far a word may be from a hint and still be taken for it. Scaled by
    /// length: two letters wrong in "cogwheel" is a mishearing, two letters wrong
    /// in "TUI" is a different word.
    static func tolerance(for length: Int) -> Int {
        switch length {
        case ...2: 0
        case 3...5: 1
        default: 2
        }
    }

    /// The most words a hint may be spread across. A recogniser splits a compound
    /// it does not know — "deckhand" into "deck hand" — but it does not scatter one
    /// term over half a sentence.
    static let maximumWindow = 3

    /// `text` with each near-miss replaced by the hint it was reaching for.
    public static func apply(_ text: String, hints: [String]) -> String {
        let terms = hints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && normalized($0).count >= 2 }
        guard !terms.isEmpty else { return text }

        let words = split(text)
        guard !words.isEmpty else { return text }

        var result = ""
        var index = 0
        while index < words.count {
            if let match = bestMatch(words, from: index, terms: terms) {
                result += match.replacement
                result += words[index + match.length - 1].separator
                index += match.length
                continue
            }
            result += words[index].text + words[index].separator
            index += 1
        }
        return result
    }

    /// The best hint for the words starting here, or nil to leave them alone.
    private static func bestMatch(
        _ words: [Word], from index: Int, terms: [String]
    ) -> Match? {
        var best: Match?
        for length in 1...maximumWindow where index + length <= words.count {
            let window = words[index..<(index + length)].map(\.text).joined(separator: " ")
            // Punctuation sitting against the term is not part of it. Kept aside
            // and put back, or replacing "cockwheel, please" eats the comma.
            let parts = trimmed(window)
            let candidate = normalized(parts.core)
            guard !candidate.isEmpty else { continue }
            for term in terms {
                let target = normalized(term)
                // Already right — spelled the way the caller spells it. Leaving it
                // alone matters: re-emitting would drop the writer's own casing.
                if parts.core == term { return nil }
                // The onset has to survive. A mishearing keeps it — "cogwheel" into
                // "cockwheel", "TUI" into "Tu Y" — while the corrections that would
                // change the sentence do not: "tree" is not "free", and "is deck
                // hand" is not "deckhand" however close the letters run.
                guard candidate.first == target.first else { continue }
                let distance = editDistance(candidate, target)
                guard distance <= tolerance(for: target.count) else { continue }
                // A longer window that fits is the better reading: "deck hand"
                // matching "deckhand" beats "deck" doing so.
                let match = Match(
                    replacement: parts.prefix + term + parts.suffix,
                    length: length,
                    distance: distance
                )
                if best == nil || distance < best!.distance
                    || (distance == best!.distance && length > best!.length) {
                    best = match
                }
            }
        }
        return best
    }

    /// The hint chosen for one window, and how much of the text it displaces.
    private struct Match {
        let replacement: String
        let length: Int
        let distance: Int
    }

    /// A window split into the punctuation around it and the term inside.
    private struct Trimmed {
        let prefix: String
        let core: String
        let suffix: String
    }

    private static func trimmed(_ window: String) -> Trimmed {
        let isPart: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        let prefix = String(window.prefix { !isPart($0) })
        let rest = window.dropFirst(prefix.count)
        let suffix = String(rest.reversed().prefix { !isPart($0) }.reversed())
        let core = String(rest.dropLast(suffix.count))
        return Trimmed(prefix: prefix, core: core, suffix: suffix)
    }

    /// Comparison form: letters and digits, lowercased. Punctuation and spacing are
    /// exactly what a recogniser gets wrong about a term it does not know.
    static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Levenshtein, two rows rather than a matrix.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs), right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        for row in 1...left.count {
            current[0] = row
            for column in 1...right.count {
                current[column] = left[row - 1] == right[column - 1]
                    ? previous[column - 1]
                    : Swift.min(previous[column - 1], previous[column], current[column - 1]) + 1
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }

    /// A word and whatever followed it, so the text can be rebuilt exactly.
    private struct Word {
        let text: String
        let separator: String
    }

    private static func split(_ text: String) -> [Word] {
        var words: [Word] = []
        var word = "", separator = ""
        for character in text {
            if character.isWhitespace {
                separator.append(character)
            } else {
                if !separator.isEmpty {
                    words.append(Word(text: word, separator: separator))
                    word = ""; separator = ""
                }
                word.append(character)
            }
        }
        if !word.isEmpty || !separator.isEmpty {
            words.append(Word(text: word, separator: separator))
        }
        return words
    }
}
