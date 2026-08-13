//
//  HotKeyProcessor.swift
//  UttCore
//

import Dependencies
import Foundation
import os

private let hotKeyLogger = Logger(subsystem: "dev.jurrejan.utt", category: "HotKey")

/// A state machine that turns keyboard events into recording commands.
///
/// Two complementary recording modes:
/// 1. **Press-and-hold**: start on press, stop on release.
/// 2. **Double-tap lock**: a quick double-tap locks recording on until the hotkey is
///    pressed again (hands-free).
///
/// # States
/// - `.idle`: waiting for hotkey activation.
/// - `.pressAndHold(startTime:)`: recording, stops when the hotkey is released.
/// - `.doubleTapLock`: recording locked on, requires an explicit press (or ESC) to stop.
///
/// # Modifier-only hotkeys
/// For hotkeys with no key component (e.g. Option-only):
/// - "press" = all required modifiers held, no key pressed.
/// - "release" = any required modifier released.
/// - A higher minimum duration floor (0.3s) guards against OS shortcut conflicts.
/// - Mouse clicks inside that floor discard silently (Option+click, Cmd+click, …);
///   after the floor they are ignored and only ESC cancels.
///
/// # Dirty state
/// After a cancel/discard, or once an unrelated chord is seen, the processor is "dirty":
/// every event is ignored until the keyboard is fully released (`key == nil, modifiers == []`).
/// This is what stops a user from *backsliding* into the hotkey by lifting the extra
/// modifiers of an unrelated combination.
///
/// # Duration policy lives elsewhere
/// This type never discards on duration at release time — a release always emits
/// `.stopRecording`. Whether that recording is short enough to throw away is decided by
/// ``RecordingDecisionEngine/decide(_:)`` downstream.
///
/// # Related
/// - ``RecordingDecisionEngine``: keep-or-discard decision for a finished recording.
/// - `KeyEvent`: input events from keyboard monitoring.
/// - `HotKey`: which key/modifiers to detect.
public struct HotKeyProcessor {
    @Dependency(\.date.now) var now

    // MARK: - Configuration

    /// The hotkey combination to detect (key + modifiers).
    public var hotkey: HotKey

    /// If true, only a double-tap activates recording (press-and-hold disabled).
    /// Only applies to key+modifier hotkeys; modifier-only always allows press-and-hold.
    public var useDoubleTapOnly: Bool

    /// If false, the quick double-tap lock gesture is disabled.
    /// Press-and-hold still works normally.
    public var doubleTapLockEnabled: Bool

    /// Minimum duration before very quick taps are considered valid.
    /// Modifier-only hotkeys additionally enforce
    /// ``RecordingDecisionEngine/modifierOnlyMinimumDuration``.
    public var minimumKeyTime: TimeInterval

    // MARK: - State

    /// Current state of the processor. Read-only outside the module; the transitions in
    /// `HotKeyProcessor+Transitions.swift` need the setter, which `private(set)` would
    /// confine to this one file.
    public internal(set) var state: State = .idle

    /// Timestamp of the most recent hotkey release (for double-tap detection).
    /// Internal, not private: the transitions live in `HotKeyProcessor+Transitions.swift`.
    var lastTapAt: Date?

    /// When true, all input is ignored until the keyboard is fully released.
    /// Internal, not private: see `lastTapAt`.
    var isDirty: Bool = false

    // MARK: - Timing Thresholds

    /// Maximum time between two hotkey releases to count as a double-tap.
    ///
    /// Responsive for an intentional double-tap, short enough to avoid accidental ones.
    public static let doubleTapThreshold: TimeInterval = 0.3

    /// Window in which a *different* key cancels a key+modifier press-and-hold.
    ///
    /// Inside 1s a different key reads as accidental; after 1s it reads as the user
    /// deliberately typing while recording. Does not apply to modifier-only hotkeys.
    public static let pressAndHoldCancelThreshold: TimeInterval = 1.0

    /// Default minimum hold time for a press to count. User-configurable.
    public static let defaultMinimumKeyTime: TimeInterval = 0.2

    // MARK: - Initialization

    /// Creates a new hotkey processor.
    /// - Parameters:
    ///   - hotkey: the key combination to detect.
    ///   - useDoubleTapOnly: if true, disables press-and-hold for key+modifier hotkeys.
    ///   - doubleTapLockEnabled: if false, disables the double-tap lock gesture.
    ///   - minimumKeyTime: minimum duration for a valid press. Modifier-only hotkeys
    ///     raise this to at least ``RecordingDecisionEngine/modifierOnlyMinimumDuration``.
    public init(
        hotkey: HotKey,
        useDoubleTapOnly: Bool = false,
        doubleTapLockEnabled: Bool = true,
        minimumKeyTime: TimeInterval = HotKeyProcessor.defaultMinimumKeyTime
    ) {
        self.hotkey = hotkey
        self.useDoubleTapOnly = useDoubleTapOnly
        self.doubleTapLockEnabled = doubleTapLockEnabled
        self.minimumKeyTime = minimumKeyTime
    }

    // MARK: - Public API

    /// True while recording is active (press-and-hold or double-tap locked).
    public var isMatched: Bool {
        switch state {
        case .idle:
            return false
        case .pressAndHold, .doubleTapLock:
            return true
        }
    }

    /// Processes a keyboard event and returns the action to take, if any.
    ///
    /// - Parameter keyEvent: the event carrying the current key and modifier state.
    /// - Returns: an output action, or nil when nothing should happen.
    ///
    /// # Processing order
    /// 1. ESC while active → immediate cancel.
    /// 2. Dirty → ignore everything until a full release.
    /// 3. Chord matches the hotkey → handle as a press.
    /// 4. Otherwise → handle as a release, or as unrelated input.
    public mutating func process(keyEvent: KeyEvent) -> Output? {
        if keyEvent.key == .escape, state != .idle {
            let previousState = String(describing: state)
            hotKeyLogger.notice("ESC cancel from state=\(previousState, privacy: .public)")
            return abort(with: .cancel)
        }

        if isDirty {
            guard chordIsFullyReleased(keyEvent) else { return nil }
            isDirty = false
        }

        if chordMatchesHotkey(keyEvent) {
            return handleMatchingChord()
        }

        // Unrelated key or extra modifiers: block re-triggering until a full release.
        if chordIsDirty(keyEvent) {
            isDirty = true
        }
        return handleNonmatchingChord(keyEvent)
    }

    /// Processes a mouse click so an accidental modifier-only activation can bow out.
    ///
    /// Modifier-only hotkeys collide with system click gestures (Option+click duplicates
    /// in Finder, Cmd+click opens a new tab, …), so a click inside the minimum window
    /// discards the recording and lets the click through untouched.
    ///
    /// - Returns: `.discard` when the recording was thrown away, nil when the click is ignored.
    ///
    /// # Behaviour
    /// - Modifier-only: discard inside the minimum window, ignore after it.
    /// - Key+modifier: always ignored — a mouse click cannot be part of that chord.
    /// - Double-tap lock: always ignored; a locked recording is intentional, only ESC cancels.
    public mutating func processMouseClick() -> Output? {
        guard hotkey.key == nil else { return nil }

        switch state {
        case .idle:
            return nil
        case let .pressAndHold(startTime):
            // Inside the floor the click is almost certainly a system gesture, not dictation.
            guard now.timeIntervalSince(startTime) < effectiveModifierOnlyMinimum else { return nil }
            return abort(with: .discard)
        case .doubleTapLock:
            return nil
        }
    }
}

// MARK: - State & Output

public extension HotKeyProcessor {
    /// Current state of hotkey detection.
    enum State: Equatable, Sendable {
        /// Idle, waiting for hotkey activation.
        case idle

        /// Press-and-hold recording is active.
        /// - Parameter startTime: when the hotkey was pressed, for duration checks.
        case pressAndHold(startTime: Date)

        /// Double-tap lock active — recording continues until an explicit stop.
        case doubleTapLock
    }

    /// Action to take in response to an input event.
    enum Output: Equatable, Sendable {
        /// Begin a new recording session.
        case startRecording

        /// Stop the current recording and hand it to the decision engine.
        case stopRecording

        /// Explicit user cancellation (ESC). Plays the cancel sound.
        case cancel

        /// Silent discard of an accidental or too-short activation.
        case discard
    }
}
