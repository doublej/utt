//
//  TranscriptHintsTests.swift
//  UttCoreTests
//
//  The first four cases are real: they came out of deckhand's log of JJ's own
//  clips on 2026-09-09, where each one destroyed the term carrying the meaning.
//

import Foundation
import Testing
@testable import UttCore

struct TranscriptHintsTests {
    @Test("the misheard terms from the log come back right")
    func correctsRealMisses() {
        #expect(
            TranscriptHints.apply("remove the cockwheel", hints: ["cogwheel"])
                == "remove the cogwheel")
        #expect(
            TranscriptHints.apply("sending messages to this Tu Y", hints: ["TUI"])
                == "sending messages to this TUI")
        #expect(
            TranscriptHints.apply("the first one is deck hand", hints: ["deckhand"])
                == "the first one is deckhand")
    }

    /// The one the caller cannot help with, and the reason this is not sold as a
    /// fix for mishearing in general: "previous tree" for "previous three" is a
    /// wrong ordinary word, and no repo vocabulary contains "three".
    @Test("a plain English mishearing is not something hints can reach")
    func leavesOrdinaryWordsAlone() {
        let hints = ["deckhand", "launchd", "onenv", "xcodegen"]
        #expect(
            TranscriptHints.apply("which the previous tree did not", hints: hints)
                == "which the previous tree did not")
    }

    /// The failure that matters. A wrong correction reads perfectly and says
    /// something else, so a hint must displace only what was nearly it already.
    @Test("a word that merely resembles a hint is left alone")
    func refusesLooseMatches() {
        #expect(TranscriptHints.apply("the docker is running", hints: ["deckhand"])
            == "the docker is running")
        #expect(TranscriptHints.apply("open the door", hints: ["Dolt"]) == "open the door")
        #expect(TranscriptHints.apply("run the tests", hints: ["rust"]) == "run the tests")
        #expect(TranscriptHints.apply("a tree fell", hints: ["free"]) == "a tree fell")
    }

    /// Short terms get no slack: two letters wrong in "cogwheel" is a mishearing,
    /// two letters wrong in "TUI" is a different word.
    @Test("tolerance is scaled by how long the term is")
    func scalesTolerance() {
        #expect(TranscriptHints.tolerance(for: 2) == 0)
        #expect(TranscriptHints.tolerance(for: 3) == 1)
        #expect(TranscriptHints.tolerance(for: 8) == 2)
    }

    @Test("punctuation and spacing around a corrected term survive")
    func keepsSurroundingText() {
        #expect(
            TranscriptHints.apply("Remove the cockwheel, please.", hints: ["cogwheel"])
                == "Remove the cogwheel, please.")
        #expect(
            TranscriptHints.apply("first line\nsecond cockwheel", hints: ["cogwheel"])
                == "first line\nsecond cogwheel")
    }

    /// A term already spelled the caller's way is left exactly as the writer had
    /// it — re-emitting the hint would flatten casing the transcript got right.
    @Test("text that is already correct is untouched")
    func leavesCorrectTextAlone() {
        let text = "the deckhand daemon is running"
        #expect(TranscriptHints.apply(text, hints: ["deckhand"]) == text)
        #expect(TranscriptHints.apply(text, hints: []) == text)
        #expect(TranscriptHints.apply("", hints: ["deckhand"]) == "")
    }

    /// A hint spread over more words than a recogniser would ever split it into is
    /// not a mishearing, it is a coincidence.
    @Test("a hint is not assembled out of a whole sentence")
    func boundsTheWindow() {
        #expect(TranscriptHints.maximumWindow == 3)
        #expect(
            TranscriptHints.apply("d e c k h a n d", hints: ["deckhand"])
                == "d e c k h a n d")
    }

    @Test("empty and one-letter hints are ignored rather than matched")
    func ignoresUselessHints() {
        #expect(TranscriptHints.apply("a b c", hints: ["", "   ", "x"]) == "a b c")
    }
}
