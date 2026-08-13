//
//  HotKeyProcessorTests.swift
//  UttCoreTests
//
//  Press-and-hold behaviour. Double-tap lock lives in +DoubleTap, dirty-state and
//  ESC handling in +EdgeCases.
//

import Testing
@testable import UttCore

struct HotKeyProcessorTests {
    // MARK: - Standard HotKey (key + modifiers) Tests

    // Tests a single key press that matches the hotkey
    @Test
    func pressAndHold_startsRecordingOnHotkey_standard() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true)
            ]
        )
    }

    @Test
    func pressAndHold_startsRecordingOnHotkey_modifierOnly() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true)
            ]
        )
    }

    // Tests releasing the hotkey stops recording
    @Test
    func pressAndHold_stopsRecordingOnHotkeyRelease_standard() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    @Test
    func pressAndHold_stopsRecordingOnHotkeyRelease_modifierOnly() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    @Test
    func pressAndHold_stopsRecordingOnHotkeyRelease_multipleModifiers() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    /// Any half of the chord coming up ends the recording. Waiting for the key meant a
    /// released modifier left it running on a combination the user had already dropped.
    @Test
    func pressAndHold_stopsWhenTheModifierIsReleasedFirst() {
        runScenario(
            hotkey: HotKey(key: .u, modifiers: [.option]),
            steps: [
                // Press modifier first (Option)
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                // Then press the key to start recording
                ScenarioStep(time: 0.05, key: .u, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Release the modifier, key still down, well past the 1s window where an
                // interruption would have been ignored. The chord is broken: stop.
                ScenarioStep(
                    time: 1.5, key: .u, modifiers: [],
                    expectedOutput: .stopRecording, expectedIsMatched: false, expectedState: .idle
                ),
                // The key coming up afterwards is nothing at all.
                ScenarioStep(time: 1.55, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false)
            ]
        )
    }

    // Tests pressing a different key cancels recording
    @Test
    func pressAndHold_cancelsOnOtherKeyPress_standard() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                // Initial hotkey press
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Different key press within cancel threshold
                ScenarioStep(time: 0.5, key: .b, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    // For modifier-only hotkeys, extra modifiers after threshold are ignored
    @Test
    func pressAndHold_ignoresExtraModifierAfterThreshold_modifierOnly() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // Initial hotkey press (option)
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Press a different modifier after threshold (0.5s > 0.3s) - should be ignored
                ScenarioStep(time: 0.5, key: nil, modifiers: [.option, .command], expectedOutput: nil, expectedIsMatched: true)
            ]
        )
    }

    // Tests that pressing a different key after threshold doesn't cancel
    @Test
    func pressAndHold_doesNotCancelAfterThreshold_standard() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                // Initial hotkey press
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Different key press after cancel threshold
                ScenarioStep(time: 1.5, key: .b, modifiers: [.command], expectedOutput: nil, expectedIsMatched: true)
            ]
        )
    }

    @Test
    func pressAndHold_doesNotCancelAfterThreshold_modifierOnly() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // Initial hotkey press
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Different modifier press after cancel threshold
                ScenarioStep(time: 1.5, key: nil, modifiers: [.option, .command], expectedOutput: nil, expectedIsMatched: true)
            ]
        )
    }

    // The user cannot "backslide" into pressing the hotkey. If the user is chording extra
    // modifiers, everything must be released before a hotkey can trigger
    @Test
    func pressAndHold_doesNotTriggerOnBackslide_standard() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                // They press the hotkey with an extra modifier
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command, .shift], expectedOutput: nil, expectedIsMatched: false),
                // And then release the extra modifier, nothing should happen
                ScenarioStep(time: 0.1, key: .a, modifiers: [.command], expectedOutput: nil, expectedIsMatched: false),
                // Then if they release everything, the hotkey should trigger
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                // And try to press the hotkey again, it should start recording
                ScenarioStep(time: 0.3, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true)
            ]
        )
    }
}
