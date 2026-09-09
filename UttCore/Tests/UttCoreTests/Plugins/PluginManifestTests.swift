//
//  PluginManifestTests.swift
//  UttCoreTests
//
//  A manifest is written by another process, so every test here is about what
//  happens when that process is wrong — or hostile.
//

import Foundation
import Testing
@testable import UttCore

struct PluginManifestTests {
    private func manifest(id: String = "deckhand", settings: [PluginSetting] = []) -> PluginManifest {
        PluginManifest(id: id, name: "Deckhand", settings: settings)
    }

    /// The id names a file utt itself will write — `plugins/<id>.values.json` — so
    /// a separator or a leading dot in it is a write outside the directory.
    @Test("an id that could escape the plugins directory is refused")
    func refusesTraversal() {
        #expect(manifest(id: "../../settings").sanitized() == nil)
        #expect(manifest(id: "deck/hand").sanitized() == nil)
        #expect(manifest(id: "..").sanitized() == nil)
        #expect(manifest(id: ".hidden").sanitized() == nil)
        #expect(manifest(id: "").sanitized() == nil)
        #expect(manifest(id: String(repeating: "a", count: 65)).sanitized() == nil)
        #expect(manifest(id: "deckhand").sanitized() != nil)
        #expect(manifest(id: "deck-hand_2.0").sanitized() != nil)
    }

    /// A newline in a label breaks the row it is drawn in, and a 4,000-character
    /// name is a rail nobody can read.
    @Test("names are flattened to one bounded line")
    func flattensText() throws {
        let wild = PluginManifest(id: "p", name: "  Deck\nhand  ", blurb: String(repeating: "x", count: 500))
        let clean = try #require(wild.sanitized())
        #expect(clean.name == "Deck hand")
        #expect(clean.blurb?.count == 120)
        #expect(PluginManifest(id: "p", name: "   ").sanitized() == nil)
    }

    /// `Image(systemName:)` draws nothing for a name that is not a symbol, which
    /// reads as a broken page rather than as a plugin that gave a bad icon.
    @Test("an implausible symbol name is dropped, not drawn")
    func dropsBadSymbol() throws {
        #expect(try #require(PluginManifest(id: "p", name: "P", systemImage: "sail boat/../x").sanitized()).systemImage == nil)
        #expect(try #require(PluginManifest(id: "p", name: "P", systemImage: "sailboat").sanitized()).systemImage == "sailboat")
    }

    /// Two rows sharing a key would share a value: editing the second would
    /// silently overwrite the first.
    @Test("a duplicate key keeps the first row only")
    func dropsDuplicateKeys() throws {
        let clean = try #require(manifest(settings: [
            PluginSetting(key: "route", kind: .string, label: "First", value: .string("a")),
            PluginSetting(key: "route", kind: .string, label: "Second", value: .string("b"))
        ]).sanitized())
        #expect(clean.settings.count == 1)
        #expect(clean.settings[0].label == "First")
    }

    @Test("a page cannot be longer than the cap")
    func capsSettings() throws {
        let many = (0..<50).map {
            PluginSetting(key: "k\($0)", kind: .bool, label: "L\($0)", value: .bool(false))
        }
        let clean = try #require(manifest(settings: many).sanitized())
        #expect(clean.settings.count == PluginManifest.maximumSettings)
    }

    /// A choice with no options is a picker that cannot be used; a default outside
    /// its own options is a picker showing nothing.
    @Test("a choice is repaired to its own options or dropped")
    func repairsChoices() throws {
        #expect(PluginSetting(key: "r", kind: .choice, label: "R", value: .string("a")).sanitized() == nil)
        let strayDefault = PluginSetting(
            key: "r", kind: .choice, label: "R", options: ["auto", "keyboard"], value: .string("socket"))
        #expect(try #require(strayDefault.sanitized()).value == .string("auto"))
    }

    /// A plugin declaring a bool and defaulting it to a string would otherwise
    /// hand SwiftUI a toggle with no boolean behind it.
    @Test("a default that disagrees with its kind is replaced")
    func repairsMistypedDefaults() throws {
        let wrong = PluginSetting(key: "k", kind: .bool, label: "K", value: .string("yes"))
        #expect(try #require(wrong.sanitized()).value == .bool(false))
    }

    /// The case that arrives in the field: the plugin shipped a new schema on top
    /// of the values file utt wrote for the old one.
    @Test("a stored value the control cannot show falls back to the default")
    func resolvesStaleStoredValues() {
        let schema = manifest(settings: [
            PluginSetting(key: "deliver", kind: .bool, label: "Deliver", value: .bool(true)),
            PluginSetting(key: "route", kind: .choice, label: "Route",
                          options: ["auto", "socket"], value: .string("auto"))
        ])
        let resolved = schema.resolved(stored: [
            "deliver": .bool(false),        // still valid — kept
            "route": .string("keyboard"),   // no longer an option — falls back
            "gone": .string("x")            // no such setting any more — ignored
        ])
        #expect(resolved.map(\.value) == [.bool(false), .string("auto")])
    }

    /// The values file is the store, so it has to survive being half-written or
    /// hand-edited without costing the user the whole page.
    @Test("a damaged values file decodes to usable defaults")
    func decodesDamagedValuesFile() throws {
        let json = Data(#"{"revision": "not a number", "values": {"a": true}}"#.utf8)
        let file = try JSONDecoder().decode(PluginValuesFile.self, from: json)
        #expect(file.revision == 0)
        #expect(file.values == ["a": .bool(true)])
        #expect(file.api == nil)
    }

    /// A watcher comparing an integer must never see it stand still or go backwards.
    @Test("the revision advances from what is on disk")
    func advancesRevision() {
        let onDisk = PluginValuesFile(revision: 41, values: ["a": .bool(true)])
        #expect(onDisk.next(values: ["a": .bool(false)], api: nil).revision == 42)
    }
}

/// Decoding tests, kept apart because they are about the *wire* format — the JSON a
/// plugin actually writes, not values built in Swift. The first version of this
/// file passed every construction test and still rejected every real manifest:
/// Swift's synthesized decoder ignores property defaults and demands every key, so
/// a `bool` setting with no `options` threw and took the whole manifest with it.
struct PluginManifestDecodingTests {
    /// Deckhand's manifest, as its daemon writes it.
    private let json = Data("""
    {
      "id": "deckhand",
      "name": "Deckhand",
      "blurb": "Relays spoken text into sessions.",
      "systemImage": "sailboat",
      "needsApi": true,
      "settings": [
        {"key": "route", "kind": "choice", "label": "Route",
         "options": ["auto", "keyboard", "socket"], "value": "auto"},
        {"key": "deliver", "kind": "bool", "label": "Send into sessions", "value": true},
        {"key": "attribution", "kind": "string", "label": "Prefix", "value": "JJ, spoken:"}
      ]
    }
    """.utf8)

    @Test("a real manifest decodes, options-less settings included")
    func decodesRealManifest() throws {
        let manifest = try #require(JSONDecoder().decode(PluginManifest.self, from: json).sanitized())
        #expect(manifest.id == "deckhand")
        #expect(manifest.needsApi)
        #expect(manifest.settings.map(\.key) == ["route", "deliver", "attribution"])
        #expect(manifest.settings.map(\.value) == [.string("auto"), .bool(true), .string("JJ, spoken:")])
    }

    /// The minimum a plugin can write and still get a page.
    @Test("a manifest of only id and name decodes")
    func decodesMinimalManifest() throws {
        let bare = Data(#"{"id": "p", "name": "P"}"#.utf8)
        let manifest = try #require(JSONDecoder().decode(PluginManifest.self, from: bare).sanitized())
        #expect(manifest.settings.isEmpty)
        #expect(!manifest.needsApi)
    }

    /// JSON `true` must not arrive as the number 1 and render a text field.
    @Test("a boolean stays a boolean through a round trip")
    func roundTripsValues() throws {
        let values = PluginValuesFile(revision: 7, values: [
            "deliver": .bool(true), "attribution": .string("JJ"), "count": .number(3)
        ])
        let decoded = try JSONDecoder().decode(
            PluginValuesFile.self, from: JSONEncoder().encode(values))
        #expect(decoded == values)
    }
}
