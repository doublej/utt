//
//  ExtensionCoverTests.swift
//  UttCoreTests
//
//  The cover is a full-screen sign raised on another process's say-so, so every
//  test here is about the two ways that goes wrong: utt being made to poll
//  somewhere it should not, and the sign staying up when it should be down.
//

import Foundation
import Testing
@testable import UttCore

struct ExtensionCoverTests {
    private func decoded(_ json: String) throws -> ExtensionManifest {
        try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    @Test("a loopback address survives decoding and sanitizing")
    func keepsLoopback() throws {
        let manifest = try decoded(#"{"id": "deck", "name": "Deck", "cover": {"url": "http://127.0.0.1:4180/health"}}"#)
        let clean = try #require(manifest.sanitized())
        #expect(clean.cover?.endpoint?.absoluteString == "http://127.0.0.1:4180/health")
        for url in ["http://localhost:4180/health", "https://LOCALHOST/x", "http://[::1]:4180/health"] {
            #expect(ExtensionCover(url: url).isUsable, "\(url)")
        }
    }

    /// A manifest is a file any local process can write. One naming a network host
    /// would have utt poll it every two seconds for as long as the extension is on.
    @Test("an address off this Mac is dropped, and the rest of the manifest kept")
    func dropsNetworkAddresses() throws {
        for url in [
            "http://192.168.1.10:4180/health", "http://deckhand.jurrejan.com/health",
            "http://127.0.0.1@evil.example/health", "http://localhost.evil.example/",
            "file:///etc/passwd", "ftp://127.0.0.1/", "127.0.0.1:4180/health", ""
        ] {
            let clean = try #require(ExtensionManifest(id: "deck", name: "Deck", cover: ExtensionCover(url: url)).sanitized())
            #expect(clean.cover == nil, "\(url)")
        }
    }

    /// Tolerant like every other key: a cover of the wrong shape costs the cover,
    /// not the whole manifest.
    @Test("a malformed cover leaves the manifest loading")
    func toleratesMalformedCover() throws {
        #expect(try decoded(#"{"id": "deck", "name": "Deck", "cover": "http://127.0.0.1/"}"#).cover == nil)
        #expect(try decoded(#"{"id": "deck", "name": "Deck", "cover": {"href": "x"}}"#).cover == nil)
        #expect(try decoded(#"{"id": "deck", "name": "Deck"}"#).cover == nil)
    }

    @Test("the answer's cover object raises the sign, and anything else lowers it")
    func readsAnswer() {
        let raised = ExtensionCover.sign(from: Data(#"{"ok": true, "cover": {"title": "On the phone", "detail": "Deckhand is driving"}}"#.utf8))
        #expect(raised == ExtensionCover.Sign(title: "On the phone", detail: "Deckhand is driving"))
        for answer in [
            #"{"ok": true}"#, #"{"cover": null}"#, #"{"cover": {}}"#, #"{"cover": {"title": "  "}}"#,
            #"{"cover": "up"}"#, #"[{"cover": {"title": "x"}}]"#, "not json", ""
        ] {
            #expect(ExtensionCover.sign(from: Data(answer.utf8)) == nil, "\(answer)")
        }
    }

    @Test("the sign's lines are flattened and bounded")
    func boundsSign() throws {
        let long = String(repeating: "x", count: 1000)
        let sign = try #require(ExtensionCover.sign(from: Data(#"{"cover": {"title": "On\nthe phone", "detail": "\#(long)"}}"#.utf8)))
        #expect(sign.title == "On the phone")
        #expect(sign.detail.count == 240)
        #expect(try #require(ExtensionCover.sign(from: Data(#"{"cover": {"title": "Up"}}"#.utf8))).detail.isEmpty)
    }

    /// The guide's examples are copied straight into a manifest and a server.
    @Test("the guide's manifest and answer examples are ones utt acts on")
    func guideExamplesWork() throws {
        let guide = ExtensionGuide.markdown(directory: "/tmp/extensions/")
        let section = try #require(guide.range(of: "## A sign over the screen: `cover`")).upperBound
        var blocks: [Data] = []
        var cursor = section
        for _ in 0 ..< 2 {
            let opening = try #require(guide.range(of: "```json\n", range: cursor ..< guide.endIndex))
            let closing = try #require(guide.range(of: "```", range: opening.upperBound ..< guide.endIndex))
            blocks.append(Data(guide[opening.upperBound ..< closing.lowerBound].utf8))
            cursor = closing.upperBound
        }
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: blocks[0])
        #expect(try #require(manifest.sanitized()).cover?.isUsable == true)
        #expect(ExtensionCover.sign(from: blocks[1]) != nil)
    }

    /// Never shown to someone at the Mac: any input resets the idle time, which takes
    /// a raised sign down and keeps further "up" answers out until the Mac is still again.
    @Test("local input outranks the extension's answer")
    func inputLowersSign() {
        let sign = ExtensionCover.Sign(title: "On the phone", detail: "")
        #expect(ExtensionCover.shown(sign, idle: 120) == sign)
        #expect(ExtensionCover.shown(sign, idle: ExtensionCover.settledIdle) == sign)
        #expect(ExtensionCover.shown(sign, idle: 0.1) == nil)
        #expect(ExtensionCover.shown(sign, idle: ExtensionCover.settledIdle - 0.5) == nil)
        #expect(ExtensionCover.shown(nil, idle: 120) == nil)
    }
}
