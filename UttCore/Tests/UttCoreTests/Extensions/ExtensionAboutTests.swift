//
//  ExtensionAboutTests.swift
//  UttCoreTests
//
//  The About section is links the person will click, written by another process.
//

import Foundation
import Testing
@testable import UttCore

struct ExtensionAboutTests {
    @Test("description and links are optional, and https is the only link that survives")
    func aboutFields() throws {
        let json = #"""
        {"id": "p", "name": "P", "description": " Does\nthings ",
         "website": "https://example.com/p", "repository": "http://github.com/x/p"}
        """#
        let clean = try #require(try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8)).sanitized())
        #expect(clean.description == "Does things")
        #expect(clean.website == "https://example.com/p")
        #expect(clean.websiteURL?.host() == "example.com")
        #expect(clean.repository == nil)

        let bare = try #require(ExtensionManifest(id: "p", name: "P").sanitized())
        #expect(bare.description == nil && bare.website == nil && bare.repository == nil)

        let long = ExtensionManifest(id: "p", name: "P", description: String(repeating: "x", count: 1000))
        #expect(long.sanitized()?.description?.count == 400)
    }

    @Test("a link is https with a host, or nothing")
    func links() {
        #expect(ExtensionManifest.link("https://example.com") == "https://example.com")
        #expect(ExtensionManifest.link("  https://example.com/a?b=c  ") == "https://example.com/a?b=c")
        #expect(ExtensionManifest.link("http://example.com") == nil)
        #expect(ExtensionManifest.link("javascript:alert(1)") == nil)
        #expect(ExtensionManifest.link("https://") == nil)
        #expect(ExtensionManifest.link("example.com") == nil)
        #expect(ExtensionManifest.link("") == nil)
    }

    @Test("a snippet keeps its lines and loses what the person cannot see")
    func snippetText() throws {
        let sneaky = ExtensionSnippet(
            label: " Add\nto Claude ", text: "\n{\r\n\t\"a\": \"b\u{202E}c\u{200B}\u{1B}[2J\"\n}\n"
        )
        let clean = try #require(sneaky.sanitized())
        #expect(clean.label == "Add to Claude")
        #expect(clean.text == "{\n\t\"a\": \"bc[2J\"\n}")
    }

    @Test("a snippet too long, blank or repeated is dropped, and there are at most four")
    func snippetLimits() {
        #expect(ExtensionSnippet(label: "L", text: String(repeating: "x", count: 2001)).sanitized() == nil)
        #expect(ExtensionSnippet(label: "L", text: " \u{200B}\n ").sanitized() == nil)
        #expect(ExtensionSnippet(label: "  ", text: "x").sanitized() == nil)
        let many = ["A", "A", "B", "C", "D", "E"].map { ExtensionSnippet(label: $0, text: "x") }
        #expect(ExtensionSnippet.kept(many).map(\.label) == ["A", "B", "C", "D"])
    }

    @Test("snippets survive decoding and sanitizing, and a manifest without them has none")
    func snippetsDecode() throws {
        let json = #"{"id": "p", "name": "P", "snippets": [{"label": "Config", "detail": "Paste it.", "text": "{}"}]}"#
        let manifest = try #require(try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8)).sanitized())
        #expect(manifest.snippets == [ExtensionSnippet(label: "Config", detail: "Paste it.", text: "{}")])
        #expect(try #require(ExtensionManifest(id: "p", name: "P").sanitized()).snippets.isEmpty)
    }

    @Test("the guide shows the keys and keeps its closing checklist")
    func guide() {
        let guide = ExtensionGuide.markdown(directory: "/x/")
        #expect(guide.contains("\"repository\""))
        #expect(guide.contains("\"snippets\""))
        #expect(guide.contains("## Implementing it"))
        #expect(!guide.contains("{{"))
    }
}
