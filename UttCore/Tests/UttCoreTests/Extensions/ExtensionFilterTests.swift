//
//  ExtensionFilterTests.swift
//  UttCoreTests
//
//  A reply is written by another process, and it lands in the paste path: what
//  utt does with a bad one is what the person sees typed into their editor.
//

import Foundation
import Testing
@testable import UttCore

struct ExtensionFilterTests {
    @Test("a manifest asks to filter, or does not")
    func decodesFlag() throws {
        let asked = try JSONDecoder().decode(
            ExtensionManifest.self,
            from: Data(#"{"id": "p", "name": "P", "filtersTranscripts": true}"#.utf8)
        )
        #expect(asked.filtersTranscripts)
        #expect(asked.sanitized()?.filtersTranscripts == true)
        let silent = try JSONDecoder().decode(
            ExtensionManifest.self, from: Data(#"{"id": "p", "name": "P"}"#.utf8))
        #expect(!silent.filtersTranscripts)
    }

    /// Nil is "no reply" and the original text goes through. An empty string is a
    /// reply — the extension decided nothing should be pasted — and is kept distinct.
    @Test("a reply utt cannot read is no reply, an empty one is a reply")
    func readsReply() {
        #expect(ExtensionFilterReply.text(in: Data(#"{"text": "  hello  "}"#.utf8)) == "hello")
        #expect(ExtensionFilterReply.text(in: Data(#"{"text": ""}"#.utf8)) == "")
        #expect(ExtensionFilterReply.text(in: Data(#"{"text": 12}"#.utf8)) == nil)
        #expect(ExtensionFilterReply.text(in: Data(#"{"answer": "x"}"#.utf8)) == nil)
        #expect(ExtensionFilterReply.text(in: Data("not json".utf8)) == nil)
        #expect(ExtensionFilterReply.text(in: Data()) == nil)
        let huge = #"{"text": ""# + String(repeating: "a", count: ExtensionFilterReply.maximumBytes) + #""}"#
        #expect(ExtensionFilterReply.text(in: Data(huge.utf8)) == nil)
    }

    @Test("the guide carries the filter contract")
    func guideMentionsFilters() {
        let guide = ExtensionGuide.markdown(directory: "/tmp/extensions/")
        #expect(guide.contains("filtersTranscripts"))
        #expect(guide.contains("/tmp/extensions/<id>.filter/"))
        #expect(!guide.contains("{{"))
    }
}
