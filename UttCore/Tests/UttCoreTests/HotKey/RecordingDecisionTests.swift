//
//  RecordingDecisionTests.swift
//  UttCoreTests
//
//  Whether a finished recording is kept or dropped, purely as a function of duration
//  and hotkey shape. No clock dependency — the context carries both timestamps.
//

import Foundation
import Testing
@testable import UttCore

struct RecordingDecisionTests {
    private func makeContext(
        hotkey: HotKey,
        minimumKeyTime: TimeInterval = 0.2,
        duration: TimeInterval?
    ) -> RecordingDecisionEngine.Context {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let start = duration.map { now.addingTimeInterval(-$0) }
        return RecordingDecisionEngine.Context(
            hotkey: hotkey,
            minimumKeyTime: minimumKeyTime,
            recordingStartTime: start,
            currentTime: now
        )
    }

    @Test
    func modifierOnlyShortPressIsDiscarded() {
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.command]), duration: 0.1)
        #expect(RecordingDecisionEngine.decide(ctx) == .discardShortRecording)
    }

    @Test
    func printableKeyShortPressStillProceeds() {
        let ctx = makeContext(hotkey: HotKey(key: .quote, modifiers: [.command]), duration: 0.1)
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }

    @Test
    func longPressModifierOnlyProceeds() {
        // Duration at modifierOnlyMinimumDuration threshold (0.3s)
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.option]), duration: 0.3)
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }

    @Test
    func missingStartTimeDefaultsToShort() {
        let ctx = RecordingDecisionEngine.Context(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            minimumKeyTime: 0.2,
            recordingStartTime: nil,
            currentTime: Date(timeIntervalSinceReferenceDate: 0)
        )
        #expect(RecordingDecisionEngine.decide(ctx) == .discardShortRecording)
    }

    // MARK: - Modifier-Only Minimum Duration Tests

    @Test
    func modifierOnly_enforcesMinimumDuration_0_3s() {
        // User sets minimumKeyTime to 0.1s, but modifier-only enforces modifierOnlyMinimumDuration (0.3s)
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.1, duration: 0.25)
        #expect(RecordingDecisionEngine.decide(ctx) == .discardShortRecording)
    }

    @Test
    func modifierOnly_proceedsWhenAboveMinimumDuration() {
        // User sets minimumKeyTime to 0.1s, recording is 0.35s (above modifierOnlyMinimumDuration)
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.1, duration: 0.35)
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }

    @Test
    func modifierOnly_respectsUserPreferenceWhenHigher() {
        // User sets minimumKeyTime to 0.5s (higher than modifierOnlyMinimumDuration)
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.5, duration: 0.4)
        #expect(RecordingDecisionEngine.decide(ctx) == .discardShortRecording)
    }

    @Test
    func printableKey_doesNotEnforceModifierOnlyMinimum() {
        // Printable key hotkeys use the user's minimumKeyTime, not modifierOnlyMinimumDuration
        let ctx = makeContext(hotkey: HotKey(key: .a, modifiers: [.command]), minimumKeyTime: 0.1, duration: 0.15)
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }
}
