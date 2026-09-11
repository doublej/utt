//
//  ProcessedTranscriptTests.swift
//  UttCoreTests
//
//  `POST /transcribe` answers with this object encoded, so its JSON is a public
//  contract: `text` has to stay exactly what it was for every client written
//  against the old response, and the new keys have to be there for the ones
//  written against this.
//

import DependenciesTestSupport
import Foundation
import Testing
@testable import UttCore

@Suite("ProcessedTranscript, as the API answers with it")
struct ProcessedTranscriptTests {
    private func body(_ transcript: ProcessedTranscript) throws -> [String: Any] {
        let data = try JSONEncoder().encode(transcript)
        let parsed = try JSONSerialization.jsonObject(with: data)
        return try #require(parsed as? [String: Any])
    }

    @Test("a client reading only `text` gets what it always got")
    func textIsUnchanged() throws {
        let body = try body(ProcessedTranscript(
            raw: "i use claude code", text: "I use Claude Code", stages: [.replacements]
        ))
        #expect(body["text"] as? String == "I use Claude Code")
        #expect(body["raw"] as? String == "i use claude code")
        #expect(body["stages"] as? [String] == ["replacements"])
    }

    /// A `Set` would hand a different order to every caller, and to the extension
    /// file that is rewritten on every transcript.
    @Test("the stages come out sorted")
    func stagesAreSorted() throws {
        let body = try body(ProcessedTranscript(
            raw: "heard", text: "typed", stages: [.hints, .cleanup, .filter, .replacements]
        ))
        #expect(body["stages"] as? [String] == ["cleanup", "filter", "hints", "replacements"])
    }

    /// Absent rather than null: a skip reason is news, and a caller that never
    /// turned cleanup on should not have to read a field about it.
    @Test("the cleanup skip reason appears only when there is one")
    func skipReasonIsOptional() throws {
        let clean = try body(ProcessedTranscript(raw: "heard", text: "heard"))
        #expect(clean["cleanupSkipped"] == nil)
        #expect(clean["stages"] as? [String] == [])

        let skipped = try body(ProcessedTranscript(
            raw: "heard", text: "heard", cleanupSkipped: .guardrail
        ))
        #expect(skipped["cleanupSkipped"] as? String == "guardrail")
    }
}

/// The breakdown beside them: how long each stretch took, which is a different
/// question from which of them changed the words.
/// A real clock, unlike the suites that only care about the words: what these
/// check is that the stretches are measured at all.
@Suite("ProcessedTranscript, timed", .dependency(\.continuousClock, ContinuousClock()))
struct ProcessedTranscriptTimingTests {
    private var settings: UttSettings {
        var settings = UttSettings()
        settings.wordRemappings = [WordRemapping(match: "claude code", replacement: "Claude Code")]
        return settings
    }

    /// A skipped stage did not run, and reporting it as zero would read as one that
    /// ran and cost nothing.
    @Test("a stage the caller skipped is absent from the breakdown, not zero")
    func skippedStagesAreNotTimed() async {
        let output = await settings.processTranscript(
            "I use claude code", skipping: [.replacements, .cleanup]
        ) { _ in .cleaned("never runs") }
        #expect(output.timings["replacements"] == nil)
        #expect(output.timings["cleanup"] == nil)
        #expect(output.timings["formatting"] != nil)
    }

    /// Cleanup is the slow one and the one most worth seeing, whichever way it went.
    @Test("cleanup is timed whether it cleaned or gave up")
    func cleanupIsTimedEitherWay() async {
        let cleaned = await settings.processTranscript("I use claude code") { .cleaned($0 + ".") }
        #expect(cleaned.timings["cleanup"] != nil)
        let skipped = await settings.processTranscript("I use claude code") { _ in .skipped(.timeout) }
        #expect(skipped.timings["cleanup"] != nil)
        #expect(skipped.stages.contains(.cleanup) == false)
    }

    /// The recogniser and the stages outside this package are measured by whoever
    /// runs them and folded in here, and a second filter adds to the first.
    @Test("a stretch measured outside the pipeline is added to the same record")
    func outsideStagesFoldIn() async {
        let output = await UttSettings().processTranscript("heard", cleanup: nil)
            .timed(.decode, .milliseconds(1800))
            .applying(.filter, text: "rewritten", took: .milliseconds(20))
            .applying(.filter, text: "rewritten again", took: .milliseconds(5))
        #expect(output.timings["decode"] == 1800)
        // One `filter` number for the chain, not one per extension.
        #expect(output.timings["filter"] == 25)
    }

    @Test("the breakdown is written beside the transcript, and only when there is one")
    func timingsAreEncodedWhenMeasured() throws {
        let bare = ProcessedTranscript(raw: "heard", text: "heard")
        let parsed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bare))
        #expect((parsed as? [String: Any])?["timings"] == nil)

        let timed = bare.timed(.decode, .milliseconds(1800))
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(timed))
        let timings = try #require((body as? [String: Any])?["timings"] as? [String: Double])
        #expect(timings == ["decode": 1800])
    }

    /// The API body is a shape other people parse, and word timings are hundreds of
    /// numbers nobody on that road asked for. They ride along in memory for the jobs
    /// lane to copy out; they are not part of the encoded transcript.
    @Test("word timings survive the pipeline and stay out of the encoded body")
    func wordsRideAlongUnencoded() async throws {
        let heard = [SpokenWord(word: "heard", start: 0.1, end: 0.4)]
        let output = await UttSettings().processTranscript("heard", cleanup: nil)
            .heard(heard)
            .timed(.decode, .milliseconds(1800))
            .applying(.filter, text: "rewritten", took: .milliseconds(20))
        // Every derived copy keeps them — nothing downstream can recover them once
        // dropped, so `applying` and `timed` have to carry them.
        #expect(output.words == heard)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(output))
        #expect((body as? [String: Any])?["words"] == nil)
    }
}
