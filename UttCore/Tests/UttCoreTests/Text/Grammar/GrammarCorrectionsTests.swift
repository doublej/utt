import Foundation
import Testing
@testable import UttCore

struct GrammarCorrectionsTests {
    @Test
    func appliesEditsWithoutShiftingTheOthers() {
        let text = "he go to the shop and buy a apple today now"
        let edits = [
            GrammarEdit(range: NSRange(location: 3, length: 2), replacement: "goes"),
            GrammarEdit(range: NSRange(location: 26, length: 1), replacement: "an")
        ]
        #expect(GrammarCorrections.apply(edits, to: text) == "he goes to the shop and buy an apple today now")
    }

    @Test
    func overBudgetAndOutOfRangeLeaveTheTextWhole() {
        let text = "one two three"
        let big = [GrammarEdit(range: NSRange(location: 0, length: 7), replacement: "x")]
        #expect(GrammarCorrections.apply(big, to: text) == text)
        let stray = [GrammarEdit(range: NSRange(location: 40, length: 2), replacement: "x")]
        #expect(GrammarCorrections.apply(stray, to: text) == text)
        #expect(GrammarCorrections.apply([], to: text) == text)
    }
}
