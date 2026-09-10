//
//  ExtensionJobResultTests.swift
//  UttCoreTests
//
//  The answer file is read by extensions already installed on people's Macs, built
//  against whatever utt wrote when they shipped. A key added here must not cost one
//  of them the answer it already knew how to read.
//

import Foundation
import Testing
@testable import UttCore

@Suite("A jobs answer, across versions of the reader")
struct ExtensionJobResultTests {
    /// An extension written against the shape utt wrote before this: text or error,
    /// and one timestamp.
    private struct OldReader: Decodable {
        var text: String?
        var error: String?
        var finishedAt: String
    }

    private func encoded(_ result: ExtensionJobResult) throws -> Data {
        try JSONEncoder().encode(result)
    }

    @Test("an answer with every new key still decodes in a reader that knows none of them")
    func oldReaderKeepsWorking() throws {
        let data = try encoded(ExtensionJobResult(
            text: "the words that were spoken",
            raw: "um the words what were spoken",
            stages: ["cleanup", "hints"],
            cleanupSkipped: "timeout",
            startedAt: "2026-09-09T17:04:09Z",
            finishedAt: "2026-09-09T17:04:11Z",
            duration: 3.4
        ))
        let old = try JSONDecoder().decode(OldReader.self, from: data)
        #expect(old.text == "the words that were spoken")
        #expect(old.error == nil)
        // The one field that was already there, and the one whose meaning changed:
        // it is now the end of the work rather than the start.
        #expect(old.finishedAt == "2026-09-09T17:04:11Z")
    }

    @Test("an answer written by an older utt still decodes here")
    func newReaderReadsOldFiles() throws {
        let json = #"{"text": "spoken", "finishedAt": "2026-09-09T17:04:11Z"}"#
        let result = try JSONDecoder().decode(ExtensionJobResult.self, from: Data(json.utf8))
        #expect(result.text == "spoken")
        #expect(result.startedAt == nil)
        #expect(result.raw == nil)
        #expect(result.stages == nil)
        #expect(result.duration == nil)
    }

    @Test("nothing absent is written as null")
    func omitsWhatItHasNothingToSay() throws {
        let data = try encoded(ExtensionJobResult(
            error: "Could not transcribe that clip.",
            startedAt: "2026-09-09T17:04:09Z",
            finishedAt: "2026-09-09T17:04:11Z"
        ))
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(parsed.keys) == ["error", "startedAt", "finishedAt"])
    }
}
