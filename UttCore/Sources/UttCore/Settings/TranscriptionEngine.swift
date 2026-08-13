import Foundation

/// Which on-device engine transcribes. Parakeet is the default and the fast path;
/// Whisper exists for languages and clips Parakeet handles poorly.
///
/// Lives in UttCore rather than the app target so `UttSettings` can store it
/// without the settings model depending on client code.
public enum TranscriptionEngine: String, Codable, CaseIterable, Sendable {
    case parakeet
    case whisper

    public var displayName: String {
        switch self {
        case .parakeet: "Parakeet TDT v3"
        case .whisper: "Whisper"
        }
    }

    /// Roughly what the default model weighs, for download estimates.
    public var approximateDownloadBytes: Int64 {
        switch self {
        case .parakeet: 461_000_000
        case .whisper: 150_000_000
        }
    }

    /// Parakeet's CoreML models are Apple Silicon only — FluidAudio throws
    /// `unsupportedPlatform` on Intel — so Whisper stops being optional there.
    public var requiresAppleSilicon: Bool {
        self == .parakeet
    }
}
