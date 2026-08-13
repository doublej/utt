//
//  HotKeyProcessorTests+EdgeCases.swift
//  UttCoreTests
//
//  Dirty state, ESC cancellation, the Fn+Arrow regression, and multi-modifier chords.
//

import Testing
@testable import UttCore

extension HotKeyProcessorTests {
    // MARK: - Edge Cases

    // Tests that after pressing a key with option, releasing the key but keeping option
    // pressed does not restart recording due to the "dirty" state
    @Test
    func pressAndHold_stopsRecordingOnKeyPressAndStaysDirty() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // Initial hotkey press (option)
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Press a different key within cancel threshold - discards silently since < minimumKeyTime
                ScenarioStep(time: 0.1, key: .c, modifiers: [.option], expectedOutput: .discard, expectedIsMatched: false),
                // Release the C
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false)
            ]
        )
    }

    // MARK: - Fn + Arrow Regression

    // After using Fn with another key (e.g., Arrow), then fully releasing, a subsequent
    // standalone Fn press should be recognized and start recording. This guards against
    // the state getting "stuck" after Fn+Arrow usage.
    @Test
    func modifierOnly_fn_triggersAfterFnPlusKeyThenFullRelease() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.fn]),
            steps: [
                // Simulate using an Arrow with Fn held (use .c as a stand-in key for arrows)
                ScenarioStep(time: 0.00, key: .c, modifiers: [.fn], expectedOutput: nil, expectedIsMatched: false),
                // Fully release everything
                ScenarioStep(time: 0.05, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                // Next standalone Fn press should trigger recording
                ScenarioStep(time: 0.20, key: nil, modifiers: [.fn], expectedOutput: .startRecording, expectedIsMatched: true),
                // Release Fn should stop recording (must exceed modifierOnlyMinimumDuration)
                ScenarioStep(time: 0.40, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    // If the user uses Fn+Key and releases only the key (keeps Fn held),
    // we must NOT trigger — no standalone Fn edge occurred.
    @Test
    func modifierOnly_fn_doesNotTriggerWhenFnRemainsHeldAfterKeyRelease() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.fn]),
            steps: [
                // Use Fn with another key (stand-in for arrow)
                ScenarioStep(time: 0.00, key: .c, modifiers: [.fn], expectedOutput: nil, expectedIsMatched: false),
                // Release the key but keep Fn held — should not start
                ScenarioStep(time: 0.05, key: nil, modifiers: [.fn], expectedOutput: nil, expectedIsMatched: false),
                // Only once the user fully releases and presses Fn again should it start
                ScenarioStep(time: 0.10, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.25, key: nil, modifiers: [.fn], expectedOutput: .startRecording, expectedIsMatched: true),
                // Must exceed modifierOnlyMinimumDuration before stopping
                ScenarioStep(time: 0.60, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    // The user presses and holds option, so it should start recording, and then after two
    // seconds he also presses command, which should not do anything.
    @Test
    func pressAndHold_staysDirtyAfterTwoSeconds() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // Initial hotkey press (option)
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Press command after two seconds
                ScenarioStep(time: 2.0, key: nil, modifiers: [.option, .command], expectedOutput: nil, expectedIsMatched: true),
                // Release command
                ScenarioStep(time: 2.1, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: true),
                // Release option
                ScenarioStep(time: 2.2, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    // MARK: - ESC Cancellation

    // Tests ESC cancellation from hold state
    @Test
    func escape_cancelsFromHold() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                // Start recording
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Press ESC
                ScenarioStep(time: 0.5, key: .escape, modifiers: [], expectedOutput: .cancel, expectedIsMatched: false)
            ]
        )
    }

    // Tests ESC cancellation from lock state
    @Test
    func escape_cancelsFromLock() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second tap (locks)
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true),
                // Now locked - press ESC
                ScenarioStep(time: 1.0, key: .escape, modifiers: [], expectedOutput: .cancel, expectedIsMatched: false)
            ]
        )
    }

    // Tests that ESC while holding hotkey doesn't restart recording
    @Test
    func escape_whileHoldingHotkey_doesNotRestart() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                // Start recording
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Press ESC while still holding hotkey
                ScenarioStep(time: 0.5, key: .escape, modifiers: [.command], expectedOutput: .cancel, expectedIsMatched: false),
                // Hotkey still held - should be ignored (dirty)
                ScenarioStep(time: 0.6, key: .a, modifiers: [.command], expectedOutput: nil, expectedIsMatched: false),
                // Full release
                ScenarioStep(time: 0.7, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                // Now pressing hotkey should work again
                ScenarioStep(time: 0.8, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true)
            ]
        )
    }

    // MARK: - Multiple Modifiers & Dirty State

    // Tests that modifier-only hotkey doesn't trigger when used with other keys
    @Test
    func modifierOnly_doesNotTriggerWithOtherKeys() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.command, .option]),
            steps: [
                // User presses cmd-option-T (keyboard shortcut)
                ScenarioStep(time: 0.0, key: .t, modifiers: [.command, .option], expectedOutput: nil, expectedIsMatched: false),
                // Release T but keep modifiers held
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command, .option], expectedOutput: nil, expectedIsMatched: false),
                // Full release
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                // Now press just cmd-option (no key) - should trigger
                ScenarioStep(time: 0.3, key: nil, modifiers: [.command, .option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Release
                ScenarioStep(time: 0.4, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    // Tests that partially releasing multiple modifiers counts as full release
    @Test
    func multipleModifiers_partialRelease() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                // Press both modifiers
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Release Command (keep Option) - should stop recording
                ScenarioStep(time: 0.5, key: nil, modifiers: [.option], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    // Tests that adding extra modifier to multiple-modifier hotkey after threshold is ignored
    @Test
    func multipleModifiers_addingExtra_ignoredAfterThreshold() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                // Press both required modifiers
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Add Shift after threshold (0.5s > 0.3s) - should be ignored
                ScenarioStep(time: 0.5, key: nil, modifiers: [.option, .command, .shift], expectedOutput: nil, expectedIsMatched: true)
            ]
        )
    }

    // Tests that changing modifiers on same key cancels within 1s
    @Test
    func keyModifier_changingModifiers_cancelsWithin1s() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                // Initial hotkey press
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Add Shift modifier while keeping same key, within 1s
                ScenarioStep(time: 0.5, key: .a, modifiers: [.command, .shift], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    // Tests that dirty state blocks all input until full release
    @Test
    func dirtyState_blocksInputUntilFullRelease() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // Start recording
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Press extra modifier - discards silently since < minimumKeyTime and goes dirty
                ScenarioStep(time: 0.1, key: nil, modifiers: [.option, .command], expectedOutput: .discard, expectedIsMatched: false),
                // Try pressing hotkey again - should be ignored (dirty)
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                // Try pressing different keys - should be ignored (dirty)
                ScenarioStep(time: 0.3, key: .c, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                // Full release - clears dirty
                ScenarioStep(time: 0.4, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                // Now hotkey works again
                ScenarioStep(time: 0.5, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true)
            ]
        )
    }

    // Tests that you can't activate by releasing extra modifiers (backslide)
    @Test
    func multipleModifiers_noBackslideActivation() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                // Press with extra modifier (doesn't match)
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option, .command, .shift], expectedOutput: nil, expectedIsMatched: false),
                // Release Shift - now matches hotkey exactly, but should NOT activate (backslide)
                ScenarioStep(time: 0.1, key: nil, modifiers: [.option, .command], expectedOutput: nil, expectedIsMatched: false),
                // Full release
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                // NOW pressing hotkey should work
                ScenarioStep(time: 0.3, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true)
            ]
        )
    }
}
