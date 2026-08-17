//
//  WordRemappingTests.swift
//  UttCoreTests
//
//  "comma" → ",". Escape sequences in the replacement are expanded; regex metacharacters
//  in the match and the replacement are not.
//

import Testing
@testable import UttCore

struct WordRemappingTests {
    @Test
    func basicRemapping() {
        let remappings = [
            WordRemapping(match: "comma", replacement: ",")
        ]
        let result = WordRemappingApplier.apply("Hello comma world", remappings: remappings)
        #expect(result == "Hello , world")
    }

    @Test
    func newlineEscapeSequence() {
        let remappings = [
            WordRemapping(match: "new line", replacement: "\\n")
        ]
        let result = WordRemappingApplier.apply("Hello new line world", remappings: remappings)
        #expect(result == "Hello \n world")
    }

    @Test
    func newParagraphEscapeSequence() {
        let remappings = [
            WordRemapping(match: "new paragraph", replacement: "\\n\\n")
        ]
        let result = WordRemappingApplier.apply("Hello new paragraph world", remappings: remappings)
        #expect(result == "Hello \n\n world")
    }

    @Test
    func tabEscapeSequence() {
        let remappings = [
            WordRemapping(match: "tab", replacement: "\\t")
        ]
        let result = WordRemappingApplier.apply("Hello tab world", remappings: remappings)
        #expect(result == "Hello \t world")
    }

    @Test
    func escapedBackslash() {
        let remappings = [
            WordRemapping(match: "backslash", replacement: "\\\\")
        ]
        let result = WordRemappingApplier.apply("Hello backslash world", remappings: remappings)
        #expect(result == "Hello \\ world")
    }

    @Test
    func literalBackslashN() {
        let remappings = [
            WordRemapping(match: "code", replacement: "\\\\n")
        ]
        let result = WordRemappingApplier.apply("Hello code world", remappings: remappings)
        #expect(result == "Hello \\n world")
    }

    @Test
    func literalDollarSign() {
        let remappings = [
            WordRemapping(match: "price", replacement: "$1")
        ]
        let result = WordRemappingApplier.apply("It costs price today", remappings: remappings)
        #expect(result == "It costs $1 today")
    }

    @Test
    func caseInsensitive() {
        let remappings = [
            WordRemapping(match: "COMMA", replacement: ",")
        ]
        let result = WordRemappingApplier.apply("Hello comma world", remappings: remappings)
        #expect(result == "Hello , world")
    }

    @Test
    func doesNotRemapInsideWords() {
        let remappings = [
            WordRemapping(match: "new", replacement: "\\n")
        ]
        let result = WordRemappingApplier.apply("renewable energy", remappings: remappings)
        #expect(result == "renewable energy")
    }

    @Test
    func disabledRemappingIgnored() {
        let remappings = [
            WordRemapping(isEnabled: false, match: "comma", replacement: ",")
        ]
        let result = WordRemappingApplier.apply("Hello comma world", remappings: remappings)
        #expect(result == "Hello comma world")
    }

    @Test
    func multipleRemappings() {
        let remappings = [
            WordRemapping(match: "comma", replacement: ","),
            WordRemapping(match: "period", replacement: "."),
            WordRemapping(match: "new line", replacement: "\\n")
        ]
        let result = WordRemappingApplier.apply("Hello comma new line world period", remappings: remappings)
        #expect(result == "Hello , \n world .")
    }

    // MARK: - matches

    // The bench's hit dot per row. Same pattern as `apply`, so a rule that lights
    // up is a rule that rewrites.

    @Test
    func matchesReportsAHit() {
        let rule = WordRemapping(match: "comma", replacement: ",")
        #expect(WordRemappingApplier.matches(rule, in: "Hello comma world"))
    }

    @Test
    func matchesRespectsWordBoundaries() {
        let rule = WordRemapping(match: "silly", replacement: "daft")
        #expect(WordRemappingApplier.matches(rule, in: "such silliness") == false)
        #expect(WordRemappingApplier.matches(rule, in: "such a silly idea"))
    }

    @Test
    func matchesIgnoresCaseAndSurroundingSpace() {
        let rule = WordRemapping(match: "  COMMA ", replacement: ",")
        #expect(WordRemappingApplier.matches(rule, in: "hello comma"))
    }

    @Test
    func anEmptyMatchNeverFires() {
        let rule = WordRemapping(match: "   ", replacement: ",")
        #expect(WordRemappingApplier.matches(rule, in: "anything at all") == false)
    }
}
