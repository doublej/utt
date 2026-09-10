//
//  ProcessedTranscriptTests.swift
//  UttCoreTests
//
//  `POST /transcribe` answers with this object encoded, so its JSON is a public
//  contract: `text` has to stay exactly what it was for every client written
//  against the old response, and the new keys have to be there for the ones
//  written against this.
//

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
