import AppKit
import Foundation
import UttCore

/// The grammar stage, on the system checker. Grammar only: spelling and
/// autocorrect would "fix" names and the Dutch/English mix, and the recogniser
/// already spells.
@MainActor
enum GrammarChecker {
    // ponytail: the synchronous call blocks the main actor for the length of one
    // dictation's analysis; the async request needs a deadline race and Sendable
    // wrappers — add them if a long transcript is ever seen to stall the UI.
    static func correct(_ text: String) -> String {
        let checker = NSSpellChecker.shared
        checker.automaticallyIdentifiesLanguages = true
        var options: [NSSpellChecker.OptionKey: Any] = [:]
        // macOS 27: wait for the full analysis instead of the quick subset.
        if #available(macOS 27.0, *) { options[NSSpellChecker.OptionKey(rawValue: "NSTextCheckingWaitForAllGrammarCheckingResultsKey")] = true }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }
        let results = checker.check(
            text, range: range, types: NSTextCheckingResult.CheckingType.grammar.rawValue, options: options,
            inSpellDocumentWithTag: tag, orthography: nil, wordCount: nil
        )
        return GrammarCorrections.apply(edits(from: results), to: text)
    }

    /// The first suggestion of each issue, in the whole string's coordinates — a
    /// detail's range is relative to the sentence its result covers.
    private static func edits(from results: [NSTextCheckingResult]) -> [GrammarEdit] {
        results.flatMap { result in
            (result.grammarDetails ?? []).compactMap { detail in
                guard let span = (detail[NSGrammarRange] as? NSValue)?.rangeValue,
                      let fix = (detail[NSGrammarCorrections] as? [String])?.first else { return nil }
                return GrammarEdit(
                    range: NSRange(location: result.range.location + span.location, length: span.length),
                    replacement: fix
                )
            }
        }
    }
}
