//
//  MouseClickTests.swift
//  UttCoreTests
//
//  Mouse clicks must not turn an Option+click into a transcription.
//

import Dependencies
import Foundation
import Testing
@testable import UttCore

struct MouseClickTests {
    @Test
    func mouseClick_discardsQuickModifierOnlyRecording() {
        var processor = makeProcessor(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.15)

        // Start recording with modifier-only hotkey
        let startOutput = atTime(0) { processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option])) }
        #expect(startOutput == .startRecording)

        // Mouse click 0.25s later (< 0.3s threshold for modifier-only) should discard silently
        let clickOutput = atTime(0.25) { processor.processMouseClick() }
        #expect(clickOutput == .discard)
    }

    @Test
    func mouseClick_ignoredAfterThreshold() {
        var processor = makeProcessor(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.15)

        // Start recording with modifier-only hotkey
        let startOutput = atTime(0) { processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option])) }
        #expect(startOutput == .startRecording)

        // Mouse click 0.35s later (> 0.3s threshold) should be ignored - only ESC cancels
        let clickOutput = atTime(0.35) { processor.processMouseClick() }
        #expect(clickOutput == nil)
    }

    @Test
    func mouseClick_ignoredInDoubleTapLock() {
        var processor = makeProcessor(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.15)

        // First tap
        atTime(0) { processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option])) }
        atTime(0.2) { processor.process(keyEvent: KeyEvent(key: nil, modifiers: [])) }

        // Second tap within threshold - should lock
        atTime(0.4) { processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option])) }
        atTime(0.5) { processor.process(keyEvent: KeyEvent(key: nil, modifiers: [])) }
        #expect(processor.state == .doubleTapLock)

        // Mouse click should be ignored - only ESC cancels locked recordings
        let clickOutput = atTime(0.6) { processor.processMouseClick() }
        #expect(clickOutput == nil)
    }

    @Test
    func mouseClick_ignoresKeyPlusModifierHotkey() {
        var processor = makeProcessor(hotkey: HotKey(key: .a, modifiers: [.command]), minimumKeyTime: 0.15)

        // Start recording with key+modifier hotkey
        let startOutput = atTime(0) { processor.process(keyEvent: KeyEvent(key: .a, modifiers: [.command])) }
        #expect(startOutput == .startRecording)

        // Mouse click should be ignored for key+modifier hotkeys
        let clickOutput = atTime(0.1) { processor.processMouseClick() }
        #expect(clickOutput == nil)
    }

    @Test
    func mouseClick_respectsHigherUserPreference() {
        var processor = makeProcessor(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.5)

        // Start recording with modifier-only hotkey
        let startOutput = atTime(0) { processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option])) }
        #expect(startOutput == .startRecording)

        // Mouse click 0.4s later (> 0.3s but < 0.5s user preference) should still discard
        let clickOutput = atTime(0.4) { processor.processMouseClick() }
        #expect(clickOutput == .discard)
    }
}

// MARK: - Helpers

private func makeProcessor(hotkey: HotKey, minimumKeyTime: TimeInterval) -> HotKeyProcessor {
    withDependencies {
        $0.date = .constant(Date(timeIntervalSince1970: 0))
    } operation: {
        HotKeyProcessor(hotkey: hotkey, minimumKeyTime: minimumKeyTime)
    }
}

/// Runs `body` with the clock pinned to `seconds` past the epoch.
@discardableResult
private func atTime<Result>(_ seconds: TimeInterval, _ body: () -> Result) -> Result {
    withDependencies {
        $0.date = .constant(Date(timeIntervalSince1970: seconds))
    } operation: {
        body()
    }
}
