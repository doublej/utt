import Foundation

/// Tuned numbers that outlive any one type.
///
/// The hotkey thresholds deliberately are *not* here: they live on the types
/// that enforce them — `HotKeyProcessor.doubleTapThreshold`,
/// `HotKeyProcessor.pressAndHoldCancelThreshold`, and
/// `RecordingDecisionEngine.modifierOnlyMinimumDuration`. Restating them would
/// give the app two numbers to disagree about.
public enum UttCoreConstants {
    /// Default for `UttSettings.minimumKeyTime`: short enough to feel instant,
    /// long enough to swallow a stray tap. Owned by the processor that enforces it.
    public static let defaultMinimumKeyTime: TimeInterval = HotKeyProcessor.defaultMinimumKeyTime

    /// Sound-effect volume before the user's multiplier. Quiet by design — the
    /// cue confirms a state change, it is not the point of the interaction.
    public static let baseSoundEffectsVolume: Double = 0.2
}
