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

    @Test("the guide shows the keys and keeps its closing checklist")
    func guide() {
        let guide = ExtensionGuide.markdown(directory: "/x/")
        #expect(guide.contains("\"repository\""))
        #expect(guide.contains("## Implementing it"))
        #expect(!guide.contains("{{"))
    }
}
