import Foundation

/// How long to keep the microphone open after the user lets go of the hotkey.
///
/// A tap delivers audio in blocks, so at the moment of release the last block is
/// still being filled — closing the file immediately truncates it and eats the final
/// consonant. Waiting one block plus a small margin recovers it.
///
/// The block length is not a constant: it depends on the device and on how busy the
/// machine is (a 1024-frame block is 21 ms at 48 kHz and 43 ms at 24 kHz, and drifts
/// under load), so the wait is derived from the measured cadence rather than
/// hard-coded. The clamp keeps a stalled or wildly noisy measurement from either
/// truncating the clip or leaving the user waiting.
public enum StopGrace {
    /// Covers the gap between "the block is full" and "the tap actually ran".
    public static let margin: Duration = .milliseconds(8)
    public static let minimum: Duration = .milliseconds(20)
    public static let maximum: Duration = .milliseconds(80)

    public static func period(tapInterval: Duration) -> Duration {
        min(max(tapInterval + margin, minimum), maximum)
    }
}
