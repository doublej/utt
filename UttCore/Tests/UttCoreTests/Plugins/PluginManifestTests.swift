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

/// The plugin's declared colour, which utt lights the menu bar with while that
/// plugin's clip is being transcribed. Another plugin-supplied string, so the same
/// rule applies: parsed strictly, refused rather than repaired — a colour utt
/// cannot read is one the plugin did not mean.
struct PluginTintTests {
    @Test("both hex forms parse, with or without the hash")
    func parsesHex() throws {
        let teal = try #require(PluginManifest.rgb(from: "#3EAFB4"))
        #expect(abs(teal.red - 62.0 / 255) < 0.001)
        #expect(abs(teal.green - 175.0 / 255) < 0.001)
        #expect(abs(teal.blue - 180.0 / 255) < 0.001)
        #expect(PluginManifest.rgb(from: "3EAFB4") == teal)
    }

    /// `#RGB` is shorthand for `#RRGGBB`: "f0a" is "ff00aa", not "0f0a00".
    @Test("three digits expand the way CSS does")
    func expandsShorthand() {
        #expect(PluginManifest.rgb(from: "#f0a") == PluginManifest.rgb(from: "#ff00aa"))
        #expect(PluginManifest.rgb(from: "#000") == PluginRGB(red: 0, green: 0, blue: 0))
        #expect(PluginManifest.rgb(from: "#fff") == PluginRGB(red: 1, green: 1, blue: 1))
    }

    @Test("anything that is not a colour is refused")
    func refusesNonColours() {
        for bad in ["", "#", "#12", "#12345", "#1234567", "teal", "#gggggg", "#3EAFB4 "] {
            #expect(PluginManifest.rgb(from: bad) == nil, "\(bad) should not parse")
        }
    }

    /// Dropped on the manifest rather than kept as a dead string, so nothing
    /// downstream has to ask whether the tint it is holding is real.
    @Test("an unreadable tint does not survive sanitizing")
    func dropsUnreadableTint() throws {
        let bad = PluginManifest(id: "p", name: "P", tint: "not a colour")
        #expect(try #require(bad.sanitized()).tint == nil)
        let good = PluginManifest(id: "p", name: "P", tint: "#3EAFB4")
        #expect(try #require(good.sanitized()).tint == "#3EAFB4")
        #expect(try #require(good.sanitized()).rgb != nil)
    }
}

/// The capabilities a plugin declares, which are what its page and its menu bar
/// item are built from. Each one is a plain flag, and each one has to survive
/// sanitizing — a capability silently dropped is a plugin that looks broken.
struct PluginCapabilityTests {
    private let json = Data("""
    {
      "id": "deckhand", "name": "Deckhand",
      "needsApi": true, "wantsTranscripts": true, "sendsAudio": true,
      "showsInMenuBar": true, "tint": "#3EAFB4",
      "daemon": {"label": "com.jurrejan.deckhand"},
      "actions": [{"key": "openLog", "label": "Open log"}]
    }
    """.utf8)

    @Test("every declared capability survives decoding and sanitizing")
    func keepsCapabilities() throws {
        let manifest = try #require(JSONDecoder().decode(PluginManifest.self, from: json).sanitized())
        #expect(manifest.needsApi)
        #expect(manifest.wantsTranscripts)
        #expect(manifest.sendsAudio)
        #expect(manifest.showsInMenuBar)
        #expect(manifest.daemon?.label == "com.jurrejan.deckhand")
        #expect(manifest.actions.map(\.key) == ["openLog"])
    }

    /// A manifest that asks for nothing gets nothing — the flags are opt-in, so an
    /// older plugin cannot acquire a menu bar item or your transcripts by omission.
    @Test("a manifest that declares nothing is given nothing")
    func defaultsToNothing() throws {
        let bare = Data(#"{"id": "p", "name": "P"}"#.utf8)
        let manifest = try #require(JSONDecoder().decode(PluginManifest.self, from: bare).sanitized())
        #expect(!manifest.needsApi)
        #expect(!manifest.wantsTranscripts)
        #expect(!manifest.sendsAudio)
        #expect(!manifest.showsInMenuBar)
        #expect(manifest.daemon == nil)
        #expect(manifest.actions.isEmpty)
    }

    /// A plugin may report on its own daemon, not reach into the system's.
    @Test("an Apple daemon label is refused")
    func refusesSystemDaemons() throws {
        let sneaky = PluginManifest(
            id: "p", name: "P", daemon: PluginDaemon(label: "com.apple.WindowServer"))
        #expect(try #require(sneaky.sanitized()).daemon == nil)
        #expect(!PluginDaemon(label: "com.apple.WindowServer").isUsable)
        #expect(!PluginDaemon(label: "../../etc/passwd").isUsable)
        #expect(PluginDaemon(label: "com.jurrejan.deckhand").isUsable)
    }
}

/// Keys are not ids. The id becomes a filename and stays lowercase; a key is just
/// a name the plugin chose, and plugins write camelCase.
struct PluginKeyTests {
    @Test("a camelCase key is kept, on both settings and actions")
    func keepsCamelCaseKeys() throws {
        let setting = PluginSetting(key: "lastRelay", kind: .bool, label: "Relay", value: .bool(true))
        #expect(try #require(setting.sanitized()).key == "lastRelay")
        let action = PluginAction(key: "openLog", label: "Open log")
        #expect(try #require(action.sanitized()).key == "openLog")
    }

    /// The id keeps the stricter rule, because it names a file and the filesystem
    /// is case-insensitive.
    @Test("an id is still lowercase only")
    func idsStayLowercase() {
        #expect(!PluginManifest.isSafeIdentifier("Deckhand"))
        #expect(PluginManifest.isSafeIdentifier("deckhand"))
        #expect(PluginManifest.isSafeKey("Deckhand"))
    }

    @Test("a key that could escape a path is still refused")
    func refusesUnsafeKeys() {
        for bad in ["", "a/b", "../x", "a b", String(repeating: "k", count: 65)] {
            #expect(!PluginManifest.isSafeKey(bad), "\(bad) should be refused")
        }
    }
}
