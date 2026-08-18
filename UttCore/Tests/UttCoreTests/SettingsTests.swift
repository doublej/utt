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
            #"{"openOnLogin": true, "minimumKeyTime": 0.25, "microphonePriority": ["builtin:mic"]}"#
        )

        #expect(decoded.openOnLogin == true)
        #expect(decoded.minimumKeyTime == 0.25)
        #expect(decoded.microphonePriority == ["builtin:mic"])
        // Everything absent stays at its default
        #expect(decoded.showDockIcon == UttSettings().showDockIcon)
        #expect(decoded.selectedModel == UttSettings().selectedModel)
        #expect(decoded.wordRemappings == UttSettings().wordRemappings)
    }

    /// A settings file written before the priority list existed still has to bring
    /// the user's chosen microphone across, or every upgrade silently resets it.
    @Test
    func legacySingleMicrophoneSeedsThePriorityList() throws {
        let decoded = try decodeSettings(#"{"selectedMicrophoneID": "builtin:mic"}"#)
        #expect(decoded.microphonePriority == ["builtin:mic"])
    }

    /// The new key wins outright — a file that has both is one the app has already
    /// rewritten, and the stale single value must not jump back to the front.
    @Test
    func priorityListWinsOverTheLegacyKey() throws {
        let decoded = try decodeSettings(
            #"{"selectedMicrophoneID": "old", "microphonePriority": ["airpods", "yeti"]}"#
        )
        #expect(decoded.microphonePriority == ["airpods", "yeti"])
    }

    /// Clearing the list back to "system default" has to stick, even while a file
    /// still carries the legacy key.
    @Test
    func anEmptyPriorityListIsNotRefilledFromTheLegacyKey() throws {
        let decoded = try decodeSettings(
            #"{"selectedMicrophoneID": "old", "microphonePriority": []}"#
        )
        #expect(decoded.microphonePriority.isEmpty)
    }

    @Test
    func roundTripPreservesCustomizedValues() throws {
        var settings = UttSettings()
        settings.hotkey = HotKey(key: .u, modifiers: [.control, .shift])
        settings.muteWhileRecording = true
        settings.microphonePriority = ["airpods", "builtin:mic"]
        settings.maxHistoryEntries = 10
        settings.minimumKeyTime = 0.42
        settings.wordRemappings = [
            WordRemapping(match: "comma", replacement: ","),
            WordRemapping(match: "um", replacement: "")
        ]
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
    func noRulesShipByDefault() {
        #expect(UttSettings().wordRemappings.isEmpty)
    }

    /// Keys a pre-0.3 file wrote for its own word-removal list are not in
    /// `CodingKeys`; they decode to nothing and the next save drops them.
    @Test
    func aLegacyWordRemovalListIsIgnored() throws {
        let payload = #"""
        {"wordRemovalsEnabled":true,
         "wordRemovals":[{"id":"\#(UUID().uuidString)","isEnabled":true,"pattern":"uh+"}]}
        """#

        #expect(try decodeSettings(payload).wordRemappings.isEmpty)
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

    // MARK: - Delivery Normalization

    @Test
    func settingsFromAnOlderBuildDeliverImmediately() throws {
        let decoded = try decodeSettings(#"{"useClipboardPaste":true}"#)

        #expect(decoded.deliveryMode == .immediate)
        #expect(decoded.showTranscriptHUD)
        #expect(decoded.hudDismissAfter == 6)
    }

    // Review gates a paste, so it means nothing when nothing is ever pasted.
    @Test
    func decodeNormalizesReviewAwayWhenPastingIsOff() throws {
        let decoded = try decodeSettings(#"{"deliveryMode":"review","useClipboardPaste":false}"#)

        #expect(decoded.deliveryMode == .immediate)
    }

    @Test
    func decodeKeepsReviewWhenPastingIsOn() throws {
        let decoded = try decodeSettings(#"{"deliveryMode":"review"}"#)

        #expect(decoded.deliveryMode == .review)
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
