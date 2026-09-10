//
//  ExtensionGuideTests.swift
//  UttCoreTests
//
//  The guide is the only documentation an extension author ever reads, and its
//  JSON blocks are copied straight into a decoder. A key that drifts out of one
//  of them is a field nobody knows to read — the same reason the OpenAPI document
//  is parsed rather than trusted.
//

import Foundation
import Testing
@testable import UttCore

@Suite("The extension guide, against what utt actually writes")
struct ExtensionGuideTests {
    private let guide = ExtensionGuide.markdown(directory: "/tmp/extensions/")

    /// The first fenced JSON block after a heading, parsed.
    private func example(after heading: String) throws -> [String: Any] {
        let section = try #require(guide.range(of: heading)).upperBound
        let opening = try #require(guide.range(of: "```json\n", range: section ..< guide.endIndex))
        let closing = try #require(guide.range(of: "```", range: opening.upperBound ..< guide.endIndex))
        let block = guide[opening.upperBound ..< closing.lowerBound]
        let parsed = try JSONSerialization.jsonObject(with: Data(block.utf8))
        return try #require(parsed as? [String: Any])
    }

    private func keys(of value: some Encodable) throws -> Set<String> {
        let parsed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        return Set(try #require(parsed as? [String: Any]).keys)
    }

    @Test("the transcripts example names every key utt writes, and no others")
    func transcriptExampleMatches() throws {
        let documented = Set(try example(after: "`<id>.transcript.json`").keys)
        let written = try keys(of: ExtensionTranscript(
            sequence: 1, text: "typed", raw: "heard", stages: ["cleanup"],
            cleanupSkipped: "timeout", finishedAt: "2026-09-09T16:58:03Z",
            duration: 3.4, timings: ["decode": 1802.5], app: "Ghostty"
        ))
        #expect(documented == written)
    }

    @Test("the jobs answer example names every key utt writes, and no others")
    func jobAnswerExampleMatches() throws {
        let documented = Set(try example(after: "writes `clip-1.json` beside it").keys)
        let written = try keys(of: ExtensionJobResult(
            text: "typed", raw: "heard", stages: ["cleanup"], cleanupSkipped: "timeout",
            startedAt: "2026-09-09T17:04:09Z", finishedAt: "2026-09-09T17:04:11Z",
            startedAtMs: 1_789_052_649_182, finishedAtMs: 1_789_052_651_511,
            duration: 3.4, timings: ["decode": 1802.5]
        ))
        #expect(documented == written)
    }

    @Test("the filter question example names every key utt writes, and no others")
    func filterExampleMatches() throws {
        let documented = Set(try example(after: "`<name>.in.json`").keys)
        let written = try keys(of: ExtensionFilterRequest(
            text: "typed", raw: "heard", stages: ["cleanup"], cleanupSkipped: "timeout",
            timings: ["decode": 1802.5]
        ))
        #expect(documented == written)
    }

    /// An extension may be handed any of them, so it has to be told what all of
    /// them mean — a reason it cannot look up is a field it ignores.
    @Test("every cleanup skip reason is explained")
    func namesEverySkipReason() {
        for reason in CleanupSkipReason.allCases {
            #expect(guide.contains("`\(reason.rawValue)`"), "\(reason.rawValue)")
        }
    }

    /// `skipsTextStages` takes these names verbatim; one missing from the guide is
    /// a stage nobody knows they can opt out of.
    @Test("every skippable text stage is named as it is written")
    func namesEveryTextStage() {
        for stage in TextStage.allCases {
            #expect(guide.contains("`\"\(stage.rawValue)\"`"), "\(stage.rawValue)")
        }
    }
}
