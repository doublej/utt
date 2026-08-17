//
//  RulePresetsTests.swift
//  UttCoreTests
//
//  The presets are ordinary remapping rules, so what is worth testing is what is
//  not obvious: seeding twice must not double the list, the spacing around
//  substituted punctuation has to come out like typed text, and a rule that
//  writes nothing must not leave its hole behind.
//

import Foundation
import Testing
@testable import UttCore

struct RulePresetsTests {
    @Test
    func seedingIsIdempotent() {
        var rules: [WordRemapping] = []
        RulePresets.appendMissing(RulePresets.punctuation, to: &rules)
        let afterFirst = rules.count
        RulePresets.appendMissing(RulePresets.punctuation, to: &rules)

        #expect(afterFirst == RulePresets.punctuation.count)
        #expect(rules.count == afterFirst)
    }

    @Test
    func seedingKeepsTheUsersOwnVersionOfARule() {
        var rules = [WordRemapping(match: "comma", replacement: " ,")]
        RulePresets.appendMissing(RulePresets.punctuation, to: &rules)

        #expect(rules.filter { $0.match == "comma" }.count == 1)
        #expect(rules.first?.replacement == " ,")
    }

    @Test
    func presetRulesGetFreshIdentifiers() {
        #expect(Set(RulePresets.punctuation.map(\.id)).count == RulePresets.punctuation.count)
        #expect(RulePresets.punctuation[0].id != RulePresets.punctuation[0].id)
    }

    @Test
    func punctuationLandsWhereItWouldHaveBeenTyped() {
        var settings = UttSettings()
        settings.wordRemappings = RulePresets.punctuation

        #expect(
            settings.applyTextTransforms(to: "hello comma world new line bye")
                == "hello, world\nbye"
        )
    }

    @Test
    func bracketsTakeTheSpaceOnTheInside() {
        var settings = UttSettings()
        settings.wordRemappings = RulePresets.punctuation

        #expect(
            settings.applyTextTransforms(to: "call it open paren twice close paren later")
                == "call it (twice) later"
        )
    }

    // MARK: - Deleting rules

    @Test
    func aDeletedWordLeavesNoHoleBehind() {
        var settings = UttSettings()
        settings.wordRemappings = [
            WordRemapping(match: "um", replacement: ""),
            WordRemapping(match: "uh", replacement: "")
        ]

        #expect(settings.applyTextTransforms(to: "Well, um, that's uh fine") == "Well, that's fine")
        #expect(settings.applyTextTransforms(to: "um uh").isEmpty)
    }

    @Test
    func aDeletingRuleDoesNotFireInsideWords() {
        var settings = UttSettings()
        settings.wordRemappings = [WordRemapping(match: "um", replacement: "")]

        #expect(settings.applyTextTransforms(to: "thumb, hummer") == "thumb, hummer")
    }

    /// Deleting is a rule like any other, so it obeys the list: disable it and the
    /// word stays, and the repair pass stays out of the way with it.
    @Test
    func aDisabledDeletingRuleKeepsTheWord() {
        var settings = UttSettings()
        settings.wordRemappings = [WordRemapping(isEnabled: false, match: "um", replacement: "")]

        #expect(settings.applyTextTransforms(to: "well,  um, fine") == "well,  um, fine")
    }

    /// The tidy pass is opt-in by consequence: a word-for-word rule must not have
    /// its surrounding spaces rearranged.
    @Test
    func wordReplacementsAreLeftAlone() {
        var settings = UttSettings()
        settings.wordRemappings = [WordRemapping(match: "claude code", replacement: "Claude Code")]

        #expect(
            settings.applyTextTransforms(to: "I use claude code , mostly")
                == "I use Claude Code , mostly"
        )
    }
}
