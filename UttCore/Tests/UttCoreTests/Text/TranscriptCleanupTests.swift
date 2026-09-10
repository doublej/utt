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

/// Where cleanup sits in the pipeline, which is the whole of what the stage adds
/// to `applyTextTransforms`.
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
        let awaited = await settings.applyTextTransforms(to: text, cleanup: nil)
        #expect(awaited == sync)
    }

    @Test("cleanup runs after the replacement rules")
    func cleanupSeesReplacedText() async {
        let seen = Received()
        _ = await settings.applyTextTransforms(to: "I use claude code") { text in
            await seen.record(text)
            return text
        }
        #expect(await seen.value == "I use Claude Code")
    }

    /// The reason cleanup goes before formatting: punctuation it puts back has to
    /// still be strippable by the user's own switch.
    @Test("formatting runs after cleanup")
    func formattingRunsAfterCleanup() async {
        var settings = self.settings
        settings.removePunctuation = true
        let output = await settings.applyTextTransforms(to: "I use claude code") { $0 + "." }
        #expect(output == "I use Claude Code")
    }

    @Test("a cleanup that fails leaves the transcript it was given")
    func failedCleanupKeepsTheTranscript() async {
        let output = await settings.applyTextTransforms(to: "I use claude code") { _ in nil }
        #expect(output == "I use Claude Code")
    }

    @Test("an extension skipping cleanup does not get it")
    func skippingCleanup() async {
        let output = await settings.applyTextTransforms(to: "I use claude code", skipping: [.cleanup]) { _ in
            "cleaned"
        }
        #expect(output == "I use Claude Code")
    }

    /// Several spike variants answered an empty transcript with the instruction
    /// text, so the model never sees one.
    @Test("empty input is never sent to cleanup")
    func emptyInputIsNeverSent() async {
        let called = Received()
        let output = await settings.applyTextTransforms(to: "   ") { text in
            await called.record(text)
            return "cleaned"
        }
        #expect(output.isEmpty)
        #expect(await called.value == nil)
    }

    private actor Received {
        var value: String?
        func record(_ text: String) { value = text }
    }
}
