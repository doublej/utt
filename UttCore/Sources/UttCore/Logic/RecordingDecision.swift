//
//  RecordingDecision.swift
//  UttCore
//

import Foundation

/// Decides whether a finished recording is kept or thrown away, based on how long it ran
/// and what kind of hotkey started it.
///
/// ``HotKeyProcessor`` never discards on duration at release time — it always emits
/// `.stopRecording`. This is where that recording is actually judged.
public struct RecordingDecisionEngine {
    /// Minimum duration for modifier-only hotkeys, so a recording cannot collide with an
    /// OS modifier gesture (Option+click duplicates in Finder, Cmd+click opens a new tab).
    ///
    /// Applied regardless of the user's `minimumKeyTime`, which can only raise it.
    public static let modifierOnlyMinimumDuration: TimeInterval = 0.3

    /// Everything needed to make a recording decision.
    public struct Context: Equatable {
        /// The hotkey configuration that triggered this recording.
        public var hotkey: HotKey

        /// The user's configured minimum key time preference.
        public var minimumKeyTime: TimeInterval

        /// When recording started (nil if no recording).
        public var recordingStartTime: Date?

        /// Current timestamp.
        public var currentTime: Date

        public init(
            hotkey: HotKey,
            minimumKeyTime: TimeInterval,
            recordingStartTime: Date?,
            currentTime: Date
        ) {
            self.hotkey = hotkey
            self.minimumKeyTime = minimumKeyTime
            self.recordingStartTime = recordingStartTime
            self.currentTime = currentTime
        }
    }

    /// The outcome for a recording.
    public enum Decision: Equatable {
        /// Too short or accidental — discard silently.
        case discardShortRecording

        /// Long enough — go on to transcription.
        case proceedToTranscription
    }

    /// Decides whether to keep or discard a recording.
    ///
    /// **Modifier-only hotkeys** (e.g. Option) must clear
    /// `max(minimumKeyTime, modifierOnlyMinimumDuration)`; the 0.3s floor always applies.
    ///
    /// **Key+modifier hotkeys** (e.g. Cmd+A) always proceed. Pressing a chord is
    /// unambiguous enough that a short one is still treated as intentional, so the
    /// duration check cannot reject them.
    public static func decide(_ context: Context) -> Decision {
        let elapsed = context.recordingStartTime.map { context.currentTime.timeIntervalSince($0) } ?? 0
        let includesPrintableKey = context.hotkey.key != nil

        let effectiveMinimum = includesPrintableKey
            ? context.minimumKeyTime
            : max(context.minimumKeyTime, modifierOnlyMinimumDuration)

        let durationIsLongEnough = elapsed >= effectiveMinimum
        return (durationIsLongEnough || includesPrintableKey) ? .proceedToTranscription : .discardShortRecording
    }
}
