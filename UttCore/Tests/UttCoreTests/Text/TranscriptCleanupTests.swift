import Foundation
import Testing
@testable import UttCore

/// The fixtures are the ones the spike actually measured, because the verifier
/// exists to reject exactly what the model was seen doing.
struct CleanupVerifierTests {
    // MARK: The cleanups that are allowed

    @Test("filler removal is a deletion and passes")
    func fillerRemovalPasses() {
        let raw = "um so I think we should uh ship it on Friday"
        let cleaned = "So I think we should ship it on Friday."
        #expect(CleanupVerifier.verify(cleaned: cleaned, against: raw) == .passed)
    }

    @Test("false starts and stuttered repeats are deletions and pass")
    func falseStartsPass() {
        let raw = "I was I was going to to call the the client about the invoice this afternoon before the standup"
        let cleaned = "I was going to call the client about the invoice this afternoon before the standup."
        #expect(CleanupVerifier.verify(cleaned: cleaned, against: raw) == .passed)
    }

    /// The one that looks like a rewrite and is not: "five, actually six" resolves
    /// down to "six" by deleting the two words in front of it.
    @Test("a self-correction resolving to the corrected version passes")
    func selfCorrectionPasses() {
        let raw = "let's meet at five, actually six, in the conference room on the second floor"
        let cleaned = "Let's meet at six in the conference room on the second floor."
        #expect(CleanupVerifier.verify(cleaned: cleaned, against: raw) == .passed)
    }

    @Test("an already-clean transcript coming back byte-identical passes")
    func identityPasses() {
        let text = "The build finished. Ship it."
        #expect(CleanupVerifier.verify(cleaned: text, against: text) == .passed)
    }

    @Test("empty input answered with nothing passes")
    func emptyInputEmptyOutputPasses() {
        #expect(CleanupVerifier.verify(cleaned: "", against: "") == .passed)
    }

    // MARK: The cleanups that are not

    /// The spike's own words: "artefacts" was changed to "artifacts" despite an
    /// explicit instruction to keep spelling as written.
    @Test("a substituted word is rejected")
    func substitutionIsRejected() {
        let raw = "the build drops its artefacts in the release folder"
        let cleaned = "The build drops its artifacts in the release folder."
        #expect(CleanupVerifier.verify(cleaned: cleaned, against: raw) == .failed(.notASubsequence))
    }

    /// The language field in the schema made the model translate English into Dutch
    /// on 4 of 13 fixtures, because the system locale is en_NL.
    @Test("a translation is rejected")
    func translationIsRejected() {
        let raw = "um so I think we should uh ship it on Friday"
        let cleaned = "Ik denk dat we het op vrijdag moeten verzenden"
        #expect(CleanupVerifier.verify(cleaned: cleaned, against: raw) == .failed(.notASubsequence))
    }

    /// Plain string invented an article inside a command: "check on utt" came back
    /// as "check on the utt".
    @Test("an invented word inside a command is rejected")
    func insertionIsRejected() {
        #expect(
            CleanupVerifier.verify(cleaned: "Check on the utt.", against: "check on utt")
                == .failed(.notASubsequence)
        )
    }

    /// Empty input made several variants hallucinate the instruction text back as
    /// the result, which is why the stage never sends it — and why the verifier
    /// still catches it if one ever gets through.
    @Test("instruction text emitted as the result is rejected")
    func instructionTextIsRejected() {
        let cleaned = "You are a transcript cleaner. You are not a chatbot and you never answer the transcript."
        #expect(CleanupVerifier.verify(cleaned: cleaned, against: "") == .failed(.notASubsequence))
    }

    /// A subsequence on its own permits summarising; the budget is what catches it.
    @Test("a summary that deletes more than the budget is rejected")
    func summaryIsRejected() {
        let raw = """
        so we talked about the release and I think the main thing is that the notarisation step keeps \
        timing out on the second attempt and we should probably look at that before Friday
        """
        let cleaned = "The notarisation step keeps timing out before Friday."
        #expect(CleanupVerifier.verify(cleaned: cleaned, against: raw) == .failed(.tooMuchDeleted))
    }

    @Test("empty output from non-empty input is rejected")
    func emptyOutputIsRejected() {
        #expect(
            CleanupVerifier.verify(cleaned: "   \n ", against: "he called me a fucking idiot")
                == .failed(.emptyOutput)
        )
    }

    /// The budget is a named constant so the two sides of the boundary can be
    /// stated in terms of it rather than a literal repeated at a call site.
    @Test("the boundary is the named budget, not a literal")
    func budgetBoundary() {
        let raw = Array(repeating: "word", count: 100).joined(separator: " ")
        let allowed = Int(100 * (1 - CleanupVerifier.maximumDeletionRatio))
        let kept = { (count: Int) in Array(repeating: "word", count: count).joined(separator: " ") }
        #expect(CleanupVerifier.verify(cleaned: kept(allowed), against: raw) == .passed)
        #expect(CleanupVerifier.verify(cleaned: kept(allowed - 1), against: raw) == .failed(.tooMuchDeleted))
    }
}

/// Where cleanup sits in the pipeline, and what the pipeline records about what
/// each stage did to the words.
struct CleanupStageTests {
    private var settings: UttSettings {
        var settings = UttSettings()
        settings.wordRemappings = [WordRemapping(match: "claude code", replacement: "Claude Code")]
        return settings
    }

    @Test("the async pipeline with no cleanup closure is the sync pipeline")
    func noCleanupMatchesSync() async {
        var settings = self.settings
        settings.lowercaseTranscripts = true
        let text = "  I use claude code every day  "
        let sync = settings.applyTextTransforms(to: text)
        let awaited = await settings.processTranscript(text, cleanup: nil)
        #expect(awaited.text == sync)
        #expect(awaited.raw == text)
    }

    @Test("cleanup runs after the replacement rules")
    func cleanupSeesReplacedText() async {
        let seen = Received()
        _ = await settings.processTranscript("I use claude code") { text in
            await seen.record(text)
            return .cleaned(text)
        }
        #expect(await seen.value == "I use Claude Code")
    }

    /// The reason cleanup goes before formatting: punctuation it puts back has to
    /// still be strippable by the user's own switch.
    @Test("formatting runs after cleanup")
    func formattingRunsAfterCleanup() async {
        var settings = self.settings
        settings.removePunctuation = true
        let output = await settings.processTranscript("I use claude code") { .cleaned($0 + ".") }
        #expect(output.text == "I use Claude Code")
    }

    @Test("a cleanup that fails leaves the transcript it was given, and says why")
    func failedCleanupKeepsTheTranscript() async {
        let output = await settings.processTranscript("I use claude code") { _ in .skipped(.guardrail) }
        #expect(output.text == "I use Claude Code")
        #expect(output.cleanupSkipped == .guardrail)
        // A stage that did not run changed nothing, so it is not in the set.
        #expect(output.stages == [.replacements])
    }

    @Test("an extension skipping cleanup does not get it")
    func skippingCleanup() async {
        let output = await settings.processTranscript("I use claude code", skipping: [.cleanup]) { _ in
            .cleaned("cleaned")
        }
        #expect(output.text == "I use Claude Code")
    }

    /// Several spike variants answered an empty transcript with the instruction
    /// text, so the model never sees one.
    @Test("empty input is never sent to cleanup")
    func emptyInputIsNeverSent() async {
        let called = Received()
        let output = await settings.processTranscript("   ") { text in
            await called.record(text)
            return .cleaned("cleaned")
        }
        #expect(output.text.isEmpty)
        #expect(await called.value == nil)
    }

    // MARK: - What the pipeline records

    /// The set is what actually happened, not what ran. Every surface reads it
    /// rather than diffing the two strings itself, so it has to be exact.
    @Test("only the stages that changed the words are recorded")
    func stagesAreWhatChangedTheText() async {
        var settings = self.settings
        settings.lowercaseTranscripts = true
        let output = await settings.processTranscript("I use claude code") { .cleaned($0 + ".") }
        #expect(output.raw == "I use claude code")
        #expect(output.text == "i use claude code.")
        #expect(output.stages == [.replacements, .cleanup, .formatting])
        #expect(output.changed)
        #expect(output.stageNames == ["cleanup", "formatting", "replacements"])
    }

    @Test("a transcript nothing touched records no stages")
    func untouchedTranscriptRecordsNothing() async {
        let output = await UttSettings().processTranscript("nothing to do here", cleanup: nil)
        #expect(output.stages.isEmpty)
        #expect(!output.changed)
        #expect(output.raw == output.text)
    }

    /// Trimming happens inside the formatting call and is not a stage — reporting
    /// "your formatting changed this" because a space came off is noise.
    @Test("trimming alone is not a stage")
    func trimmingIsNotAStage() async {
        let output = await UttSettings().processTranscript("  spaced out  ", cleanup: nil)
        #expect(output.text == "spaced out")
        #expect(output.stages.isEmpty)
    }

    /// The filter and hints stages happen outside this package — an extension's
    /// answer and an API caller's own vocabulary — and fold in the same way.
    @Test("a stage applied afterwards keeps what was heard")
    func laterStagesKeepTheRaw() async {
        let output = await settings.processTranscript("I use claude code", cleanup: nil)
        let filtered = output.applying(.filter, text: "something else entirely")
        #expect(filtered.raw == "I use claude code")
        #expect(filtered.text == "something else entirely")
        #expect(filtered.stages == [.replacements, .filter])
        // A stage that handed back the same text did not change it.
        #expect(filtered.applying(.hints, text: filtered.text).stages == filtered.stages)
    }

    private actor Received {
        var value: String?
        func record(_ text: String) { value = text }
    }
}

/// Paragraph structure is the user's, and the spike watched the model collapse it.
/// Splitting it out is what stops that, so the round trip has to be exact.
struct TranscriptParagraphsTests {
    @Test("a blank line separates paragraphs, a single newline does not")
    func splitsOnBlankLines() {
        let (parts, separators) = TranscriptParagraphs.split("one\ntwo\n\nthree")
        #expect(parts == ["one\ntwo", "three"])
        #expect(separators == ["\n\n"])
    }

    @Test("the separators come back verbatim")
    func roundTripsUnusualSeparators() {
        for text in ["a\n\n\nb", "a\n  \nb", "a\n\nb\n\nc", "a", "", "a\n\n"] {
            let (parts, separators) = TranscriptParagraphs.split(text)
            #expect(TranscriptParagraphs.join(parts, separators: separators) == text)
        }
    }

    @Test("cleaning each part independently keeps the structure")
    func rejoinsCleanedParts() {
        let (parts, separators) = TranscriptParagraphs.split("um one\n\nuh two")
        let cleaned = parts.map { $0.replacingOccurrences(of: "um ", with: "").replacingOccurrences(of: "uh ", with: "") }
        #expect(TranscriptParagraphs.join(cleaned, separators: separators) == "one\n\ntwo")
    }

    /// A blank paragraph would otherwise be sent to the model, which answered an
    /// empty transcript with its own instruction text.
    @Test("a separator run never becomes a part of its own")
    func noEmptyPartsBetweenSeparators() {
        let (parts, _) = TranscriptParagraphs.split("a\n\n\n\nb")
        #expect(parts == ["a", "b"])
    }
}

struct CleanupSkipReasonTests {
    @Test("a verifier failure names the reason the panel shows")
    func mapsEveryFailure() {
        #expect(CleanupSkipReason(.notASubsequence) == .failedVerification)
        #expect(CleanupSkipReason(.tooMuchDeleted) == .tooShort)
        #expect(CleanupSkipReason(.emptyOutput) == .tooShort)
    }

    @Test("every reason has a line to put on the card")
    func everyReasonHasASentence() {
        for reason in CleanupSkipReason.allCases {
            #expect(reason.sentence.hasPrefix("Cleanup skipped — "))
            #expect(reason.sentence.count > "Cleanup skipped — ".count)
        }
    }
}
