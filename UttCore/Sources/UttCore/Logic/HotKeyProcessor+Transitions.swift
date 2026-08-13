//
//  HotKeyProcessor+Transitions.swift
//  UttCore
//
//  State transitions and chord predicates for `HotKeyProcessor`.
//

import Foundation

// MARK: - Transitions

extension HotKeyProcessor {
    /// True when the hotkey should only arm on a double-tap.
    /// Modifier-only hotkeys are excluded: they always allow press-and-hold.
    var isDoubleTapOnlyEnabledForCurrentHotkey: Bool {
        useDoubleTapOnly && doubleTapLockEnabled && hotkey.key != nil
    }

    /// The floor a modifier-only recording has to clear before unrelated input stops
    /// discarding it. Never lower than 0.3s, so OS chords like Option+click stay usable.
    var effectiveModifierOnlyMinimum: TimeInterval {
        max(minimumKeyTime, RecordingDecisionEngine.modifierOnlyMinimumDuration)
    }

    /// Handles an event whose chord *is* the configured hotkey — i.e. a press.
    ///
    /// # Transitions
    /// - `.idle` → `.pressAndHold`: start a recording (unless double-tap-only is on).
    /// - `.pressAndHold` → unchanged: already recording.
    /// - `.doubleTapLock` → `.idle`: the press is the user stopping a locked recording.
    ///
    /// # Double-tap-only mode
    /// For key+modifier hotkeys with `useDoubleTapOnly`, the first press only records a
    /// timestamp — recording starts on the second tap's release, in `handleIdleRelease`.
    mutating func handleMatchingChord() -> Output? {
        switch state {
        case .idle:
            guard !isDoubleTapOnlyEnabledForCurrentHotkey else {
                lastTapAt = now
                return nil
            }
            state = .pressAndHold(startTime: now)
            return .startRecording

        case .pressAndHold:
            return nil

        case .doubleTapLock:
            resetToIdle()
            return .stopRecording
        }
    }

    /// Handles an event whose chord is *not* the configured hotkey.
    ///
    /// Three things can hide behind that: the hotkey being released, unrelated input
    /// arriving mid-recording, or (in double-tap-only mode) the release that completes
    /// a double-tap.
    mutating func handleNonmatchingChord(_ event: KeyEvent) -> Output? {
        switch state {
        case .idle:
            return handleIdleRelease(event)

        case let .pressAndHold(startTime):
            guard !chordIsReleased(event) else { return handleHotkeyRelease() }
            return handleInterruption(elapsed: now.timeIntervalSince(startTime))

        case .doubleTapLock:
            return handleLockedRelease(event)
        }
    }

    /// A release while idle. In double-tap-only mode this is the tap landing inside the
    /// double-tap window, which arms the lock and starts recording.
    ///
    /// Releasing the *chord*, not the keyboard: with Ctrl+P the user holds Ctrl down and
    /// taps P, so demanding a bare keyboard here meant the gesture could never complete.
    mutating func handleIdleRelease(_ event: KeyEvent) -> Output? {
        guard isDoubleTapOnlyEnabledForCurrentHotkey,
              chordIsReleased(event),
              let previousTapAt = lastTapAt
        else { return nil }

        if now.timeIntervalSince(previousTapAt) < Self.doubleTapThreshold {
            state = .doubleTapLock
            return .startRecording
        }

        // Too slow to be a double-tap — forget it and wait for a fresh first tap.
        lastTapAt = nil
        return nil
    }

    /// The hotkey was released during press-and-hold.
    ///
    /// Two releases inside ``HotKeyProcessor/doubleTapThreshold`` engage the lock, and the
    /// recording keeps running with no output. Otherwise this is a normal stop, and the
    /// release time is remembered so the *next* release can complete a double-tap.
    ///
    /// Note: the elapsed duration is deliberately not consulted here. A release always
    /// emits `.stopRecording`; ``RecordingDecisionEngine/decide(_:)`` throws the recording
    /// away if it turns out to be too short.
    mutating func handleHotkeyRelease() -> Output? {
        if doubleTapLockEnabled,
           let previousReleaseAt = lastTapAt,
           now.timeIntervalSince(previousReleaseAt) < Self.doubleTapThreshold {
            state = .doubleTapLock
            return nil
        }

        state = .idle
        lastTapAt = doubleTapLockEnabled ? now : nil
        return .stopRecording
    }

    /// Unrelated input arrived while press-and-hold was recording.
    ///
    /// **Modifier-only hotkeys** — inside the 0.3s floor the activation was accidental
    /// (Option+A for "å", Cmd+click, …): discard silently and let the chord through.
    /// After the floor, ignore it and keep recording; only ESC cancels.
    ///
    /// **Key+modifier hotkeys** — inside 1s the other key reads as accidental, so stop
    /// (or discard, if we never cleared `minimumKeyTime`). After 1s the user is typing
    /// while dictating on purpose, so ignore it.
    mutating func handleInterruption(elapsed: TimeInterval) -> Output? {
        guard hotkey.key != nil else {
            guard elapsed < effectiveModifierOnlyMinimum else { return nil }
            return abort(with: .discard)
        }

        guard elapsed < Self.pressAndHoldCancelThreshold else { return nil }
        return abort(with: elapsed < minimumKeyTime ? .discard : .stopRecording)
    }

    /// While locked, everything is ignored except pressing the hotkey again — with one
    /// exception: a key+modifier hotkey in double-tap-only mode stops when the chord is
    /// released, because its press already arrived as the matching chord.
    mutating func handleLockedRelease(_ event: KeyEvent) -> Output? {
        guard isDoubleTapOnlyEnabledForCurrentHotkey, chordIsReleased(event) else {
            return nil
        }
        resetToIdle()
        return .stopRecording
    }
}

// MARK: - Helpers

extension HotKeyProcessor {
    /// True when the event is exactly the configured hotkey.
    ///
    /// Key+modifier: key and modifiers must both match exactly.
    /// Modifier-only: modifiers match exactly and no key is down.
    func chordMatchesHotkey(_ event: KeyEvent) -> Bool {
        guard hotkey.key != nil else {
            return event.key == nil && event.modifiers.matchesExactly(hotkey.modifiers)
        }
        return event.key == hotkey.key && event.modifiers.matchesExactly(hotkey.modifiers)
    }

    /// True when the event carries keys or modifiers that are not part of the hotkey.
    ///
    /// "Dirty" means the user is doing something unrelated, so every event is ignored
    /// until the keyboard is fully released. Without this, lifting the extra modifiers of
    /// an unrelated chord would leave the bare hotkey held and re-trigger a recording.
    func chordIsDirty(_ event: KeyEvent) -> Bool {
        guard hotkey.key != nil else {
            // Any key at all, or any modifier beyond the hotkey's, is unrelated input.
            return event.key != nil || !event.modifiers.isSubset(of: hotkey.modifiers)
        }
        let isSubset = event.modifiers.isSubset(of: hotkey.modifiers)
        let isWrongKey = event.key != nil && event.key != hotkey.key
        return !isSubset || isWrongKey
    }

    /// True when nothing at all is held. This is the only thing that clears `isDirty`.
    func chordIsFullyReleased(_ event: KeyEvent) -> Bool {
        event.key == nil && event.modifiers.isEmpty
    }

    /// True when the chord has fallen apart without anything new arriving: **any** part
    /// of the hotkey let go, and nothing outside the hotkey held.
    ///
    /// The "any part" is the point. Ctrl+P used to end only when P came up, so releasing
    /// Ctrl while P stayed down left the recording running on a chord the user had
    /// visibly abandoned. Letting go of either half ends it now.
    ///
    /// Something *extra* — a different key, a modifier the hotkey does not name — is not
    /// a release. That is an interruption, and `handleInterruption` decides whether it
    /// reads as a mistake or as the user typing while dictating.
    ///
    /// Modifier-only (Option): `hotkey.key` is nil, so the first guard demands no key at
    /// all and the rest reduces to "the required modifiers are no longer all held".
    func chordIsReleased(_ event: KeyEvent) -> Bool {
        guard event.key == nil || event.key == hotkey.key else { return false }
        guard event.modifiers.isSubset(of: hotkey.modifiers) else { return false }
        return !chordMatchesHotkey(event)
    }

    /// Returns to idle and blocks further input until a full release.
    /// Used for every cancel/discard path, never for a clean stop.
    mutating func abort(with output: Output) -> Output {
        isDirty = true
        resetToIdle()
        return output
    }

    /// Clears the active recording state. Deliberately leaves `isDirty` alone so a caller
    /// that set it keeps blocking input across the transition.
    mutating func resetToIdle() {
        state = .idle
        lastTapAt = nil
    }
}
