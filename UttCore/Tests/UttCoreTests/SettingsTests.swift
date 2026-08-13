//
//  SettingsTests.swift
//  UttCoreTests
//
//  UttSettings is a plain Codable struct: every key decodes with
//  `decodeIfPresent ?? default`, so an older or hand-edited settings file never fails
//  to load — absent keys fall back to the default rather than throwing.
//
//  Note: optionals that default to nil cannot round-trip a nil through
//  `decodeIfPresent ?? default`, so the assertions below only round-trip present values.
//

import Foundation
import Testing
@testable import UttCore

struct SettingsTests {
    // MARK: - Codable Contract

    @Test
    func roundTripPreservesDefaults() throws {
        let settings = UttSettings()
        #expect(try roundTrip(settings) == settings)
    }

    @Test
    func missingKeysDecodeToDefaults() throws {
        let decoded = try decodeSettings("{}")
        #expect(decoded == UttSettings())
    }

    @Test
    func unknownKeysAreIgnored() throws {
        let decoded = try decodeSettings(#"{"aSettingWeRemoved": 42, "anotherOne": "gone"}"#)
        #expect(decoded == UttSettings())
    }

    @Test
    func partialPayloadOverridesOnlyPresentKeys() throws {
        let decoded = try decodeSettings(
            #"{"openOnLogin": true, "minimumKeyTime": 0.25, "selectedMicrophoneID": "builtin:mic"}"#
        )

        #expect(decoded.openOnLogin == true)
        #expect(decoded.minimumKeyTime == 0.25)
        #expect(decoded.selectedMicrophoneID == "builtin:mic")
        // Everything absent stays at its default
        #expect(decoded.showDockIcon == UttSettings().showDockIcon)
        #expect(decoded.selectedModel == UttSettings().selectedModel)
        #expect(decoded.wordRemovals == UttSettings().wordRemovals)
    }

    @Test
    func roundTripPreservesCustomizedValues() throws {
        var settings = UttSettings()
        settings.hotkey = HotKey(key: .u, modifiers: [.control, .shift])
        settings.muteWhileRecording = true
        settings.selectedMicrophoneID = "builtin:mic"
        settings.maxHistoryEntries = 10
        settings.minimumKeyTime = 0.42
        settings.wordRemovals = [WordRemoval(pattern: "uh+")]
        settings.wordRemappings = [WordRemapping(match: "comma", replacement: ",")]
        settings.lowercaseTranscripts = true
        settings.removePunctuation = true

        #expect(try roundTrip(settings) == settings)
    }

    // MARK: - Defaults

    @Test
    func preRollEnabledByDefault() {
        #expect(UttSettings().preRollEnabled)
    }

    @Test
    func fillerWordRemovalShipsDisabled() {
        #expect(UttSettings().wordRemovalsEnabled == false)
        #expect(UttSettings().wordRemovals.map(\.pattern) == ["uh+", "um+", "er+", "hm+"])
    }

    // MARK: - Double-Tap Normalization

    // Double-tap-only is meaningless without the double-tap lock: the two must never
    // be persisted in the contradictory (true, false) combination.
    @Test
    func decodeNormalizesDoubleTapOnlyWhenLockDisabled() throws {
        let decoded = try decodeSettings(#"{"useDoubleTapOnly":true,"doubleTapLockEnabled":false}"#)

        #expect(decoded.useDoubleTapOnly == false)
        #expect(decoded.doubleTapLockEnabled == false)
    }

    @Test
    func decodeKeepsDoubleTapOnlyWhenLockDefaultsToEnabled() throws {
        let decoded = try decodeSettings(#"{"useDoubleTapOnly":true}"#)

        #expect(decoded.useDoubleTapOnly == true)
        #expect(decoded.doubleTapLockEnabled == true)
    }

    @Test
    func roundTripNormalizesAContradictoryPairWrittenByHand() throws {
        var settings = UttSettings()
        settings.useDoubleTapOnly = true
        settings.doubleTapLockEnabled = false

        let decoded = try roundTrip(settings)

        #expect(decoded.useDoubleTapOnly == false)
        #expect(decoded.doubleTapLockEnabled == false)
    }
}

// MARK: - Helpers

private func roundTrip(_ settings: UttSettings) throws -> UttSettings {
    let data = try JSONEncoder().encode(settings)
    return try JSONDecoder().decode(UttSettings.self, from: data)
}

private func decodeSettings(_ json: String) throws -> UttSettings {
    try JSONDecoder().decode(UttSettings.self, from: Data(json.utf8))
}
