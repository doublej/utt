import DependenciesTestSupport
import Foundation
import Testing
@testable import UttCore

/// An extension naming a stage is the one caller that gets a different transcript from
/// everyone else, so the two things worth pinning down are that skipping actually
/// skips and that naming nothing changes nothing.
/// The clock the pipeline times itself on never moves here: these tests are about
/// what it does to the words, not how long it took.
@Suite(.dependency(\.continuousClock, .immediate))
struct TextStageSkipTests {
    private var settings: UttSettings {
        var settings = UttSettings()
        settings.wordRemappings = [WordRemapping(match: "claude code", replacement: "Claude Code")]
        settings.lowercaseTranscripts = true
        return settings
    }

    @Test("skipping nothing is the pipeline every other caller gets")
    func defaultIsUnchanged() {
        let text = "I use claude code"
        #expect(settings.applyTextTransforms(to: text) == settings.applyTextTransforms(to: text, skipping: []))
    }

    /// The case the field exists for: a terminal wants the user's spelling of a
    /// product name and does not want the line lowercased on the way past.
    @Test("formatting can be skipped while the replacement rules still run")
    func skipFormattingKeepsReplacements() {
        let output = settings.applyTextTransforms(to: "I use claude code", skipping: [.formatting])
        #expect(output == "I use Claude Code")
    }

    @Test("replacements can be skipped while formatting still runs")
    func skipReplacementsKeepsFormatting() {
        let output = settings.applyTextTransforms(to: "I use claude code", skipping: [.replacements])
        #expect(output == "i use claude code")
    }

    @Test("skipping both leaves the recogniser's own words, trimmed")
    func skipEverything() {
        let output = settings.applyTextTransforms(to: "  I use claude code  ", skipping: [.replacements, .formatting])
        #expect(output == "I use claude code")
    }

    /// Forgiving like every other manifest key: a name from a later utt must not
    /// take the names this one does understand down with it.
    @Test("an unknown stage name is dropped and the known ones survive")
    func unknownStageIsDropped() throws {
        let json = #"{"id":"deckhand","name":"Deckhand","skipsTextStages":["formatting","teleport"]}"#
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
        #expect(manifest.skipsTextStages == [.formatting])
        #expect(manifest.sanitized()?.skipsTextStages == [.formatting])
    }

    @Test("a manifest that says nothing skips nothing")
    func absentKeyMeansNoSkipping() throws {
        let json = #"{"id":"deckhand","name":"Deckhand"}"#
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
        #expect(manifest.skipsTextStages.isEmpty)
    }
}
