//
//  HotKeyProcessorTests+DoubleTap.swift
//  UttCoreTests
//
//  Quick double-tap locks recording until the hotkey is pressed again.
//

import Foundation
import Testing
@testable import UttCore

extension HotKeyProcessorTests {
    // Tests double-tap to lock recording
    @Test
    func doubleTapLock_startsRecordingOnDoubleTap_standard() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Release all modifiers
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                // Press modifier again
                ScenarioStep(time: 0.15, key: nil, modifiers: [.command], expectedOutput: nil, expectedIsMatched: false),
                // Second tap within threshold
                ScenarioStep(time: 0.2, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Second release (should stay recording)
                ScenarioStep(time: 0.3, key: nil, modifiers: [.command], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock)
            ]
        )
    }

    @Test
    func doubleTapLock_startsRecordingOnDoubleTap_modifierOnly() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second tap within threshold
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Second release (should stay recording)
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock)
            ]
        )
    }

    @Test
    func doubleTapLock_startsRecordingOnDoubleTap_multipleModifiers() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.05, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [.option], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second tap within threshold
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Second release (should stay recording)
                ScenarioStep(time: 0.3, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock)
            ]
        )
    }

    // Tests that a slow double tap doesn't lock recording
    @Test
    func doubleTapLock_ignoresSlowDoubleTap_standard() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second tap after threshold
                ScenarioStep(time: 0.4, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true)
            ]
        )
    }

    @Test
    func doubleTapLock_ignoresSlowDoubleTap_modifierOnly() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second tap after threshold
                ScenarioStep(time: 0.4, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true)
            ]
        )
    }

    // Tests that tapping again after double-tap lock stops recording
    @Test
    func doubleTapLock_stopsRecordingOnNextTap_standard() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second tap within threshold
                ScenarioStep(time: 0.2, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Second release (should stay recording)
                ScenarioStep(time: 0.3, key: nil, modifiers: [.command], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
                // Third tap to stop recording
                ScenarioStep(time: 1.0, key: .a, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    @Test
    func doubleTapLock_stopsRecordingOnNextTap_modifierOnly() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second tap within threshold
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Second release (should stay recording)
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
                // Third tap to stop recording
                ScenarioStep(time: 1.0, key: nil, modifiers: [.option], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    @Test
    func doubleTapLock_disabled_staysPressAndHold_standard() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            doubleTapLockEnabled: false,
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Release all modifiers
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                // Press modifier again
                ScenarioStep(time: 0.15, key: nil, modifiers: [.command], expectedOutput: nil, expectedIsMatched: false),
                // Second tap within threshold
                ScenarioStep(time: 0.2, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                // Second release should stop normally (no lock)
                ScenarioStep(time: 0.3, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false, expectedState: .idle)
            ]
        )
    }

    @Test
    func doubleTapOnly_ignoredWhenDoubleTapLockDisabled() {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            useDoubleTapOnly: true,
            doubleTapLockEnabled: false,
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    // Tests that double-tap lock only engages after the second release, not the second press
    @Test
    func doubleTap_onlyLocksAfterSecondRelease() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second tap within threshold - should start a new recording but not lock yet
                ScenarioStep(
                    time: 0.2,
                    key: nil,
                    modifiers: [.option],
                    expectedOutput: .startRecording,
                    expectedIsMatched: true,
                    expectedState: .pressAndHold(startTime: Date(timeIntervalSince1970: 0.2))
                ),
                // Second release - NOW it should lock
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock)
            ]
        )
    }

    // Tests that if second tap is held too long, it's treated as a new press-and-hold
    // instead of double-tap
    @Test
    func doubleTap_secondTapHeldTooLongBecomesHold() {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                // First tap
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // First release
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                // Second press within threshold
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                // Hold for 2 seconds (should stay in press-and-hold mode)
                ScenarioStep(time: 2.2, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: true),
                // Release - should stop recording since it was a hold
                ScenarioStep(time: 2.3, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false)
            ]
        )
    }

    /// Ctrl held down throughout, P tapped twice. Demanding a bare keyboard for the
    /// release made this gesture impossible to perform — the modifier never came up.
    @Test
    func doubleTapOnly_completesWithTheModifierStillHeld() {
        runScenario(
            hotkey: HotKey(key: .p, modifiers: [.control]),
            useDoubleTapOnly: true,
            steps: [
                // Ctrl goes down and stays down for the whole scenario.
                ScenarioStep(time: 0.0, key: nil, modifiers: [.control], expectedOutput: nil, expectedIsMatched: false),
                // First tap of P: arms the window, starts nothing.
                ScenarioStep(time: 0.1, key: .p, modifiers: [.control], expectedOutput: nil, expectedIsMatched: false),
                // Releasing P — Ctrl still down — completes it and locks recording on.
                ScenarioStep(
                    time: 0.2, key: nil, modifiers: [.control],
                    expectedOutput: .startRecording, expectedIsMatched: true,
                    expectedState: .doubleTapLock
                ),
                // Tapping P again stops it — on the press, as every lock does — again
                // without Ctrl ever coming up.
                ScenarioStep(
                    time: 1.0, key: .p, modifiers: [.control],
                    expectedOutput: .stopRecording, expectedIsMatched: false, expectedState: .idle
                ),
                ScenarioStep(time: 1.1, key: nil, modifiers: [.control], expectedOutput: nil, expectedIsMatched: false)
            ]
        )
    }
}
