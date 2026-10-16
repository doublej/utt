//
//  ExtensionAboutTests.swift
//  UttCoreTests
//
//  How an extension presents itself, written by another process: the About
//  section's links the person will click, and the colour it lights the menu bar with.
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

/// The extension's declared colour, which utt lights the menu bar with while that
/// extension's clip is being transcribed. Another extension-supplied string, so the same
/// rule applies: parsed strictly, refused rather than repaired — a colour utt
/// cannot read is one the extension did not mean.
struct ExtensionTintTests {
    @Test("both hex forms parse, with or without the hash")
    func parsesHex() throws {
        let teal = try #require(ExtensionManifest.rgb(from: "#3EAFB4"))
        #expect(abs(teal.red - 62.0 / 255) < 0.001)
        #expect(abs(teal.green - 175.0 / 255) < 0.001)
        #expect(abs(teal.blue - 180.0 / 255) < 0.001)
        #expect(ExtensionManifest.rgb(from: "3EAFB4") == teal)
    }

    /// `#RGB` is shorthand for `#RRGGBB`: "f0a" is "ff00aa", not "0f0a00".
    @Test("three digits expand the way CSS does")
    func expandsShorthand() {
        #expect(ExtensionManifest.rgb(from: "#f0a") == ExtensionManifest.rgb(from: "#ff00aa"))
        #expect(ExtensionManifest.rgb(from: "#000") == ExtensionRGB(red: 0, green: 0, blue: 0))
        #expect(ExtensionManifest.rgb(from: "#fff") == ExtensionRGB(red: 1, green: 1, blue: 1))
    }

    @Test("anything that is not a colour is refused")
    func refusesNonColours() {
        for bad in ["", "#", "#12", "#12345", "#1234567", "teal", "#gggggg", "#3EAFB4 "] {
            #expect(ExtensionManifest.rgb(from: bad) == nil, "\(bad) should not parse")
        }
    }

    /// Dropped on the manifest rather than kept as a dead string, so nothing
    /// downstream has to ask whether the tint it is holding is real.
    @Test("an unreadable tint does not survive sanitizing")
    func dropsUnreadableTint() throws {
        let bad = ExtensionManifest(id: "p", name: "P", tint: "not a colour")
        #expect(try #require(bad.sanitized()).tint == nil)
        let good = ExtensionManifest(id: "p", name: "P", tint: "#3EAFB4")
        #expect(try #require(good.sanitized()).tint == "#3EAFB4")
        #expect(try #require(good.sanitized()).rgb != nil)
    }
}
