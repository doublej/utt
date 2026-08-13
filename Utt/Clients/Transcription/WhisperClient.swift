import Dependencies
import Foundation
import WhisperKit
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "whisper")

/// WhisperKit via `argmaxinc/argmax-oss-swift` 1.1.0.
///
/// The package was renamed from `argmaxinc/WhisperKit` and the SPM identity changed
/// with it (`whisperkit` → `argmax-oss-swift`), so this cannot be an in-place bump
/// from the old 0.15.0 pin. The **module** is still `WhisperKit`. We depend on the
/// `WhisperKit` product rather than the `ArgmaxOSS` umbrella, which would drag in
/// TTSKit and SpeakerKit for nothing.
///
/// API differences from the 0.15.x the reference client is written against, all of
/// which bite if you paste that client verbatim: the single-result `transcribe`
/// overloads are gone
/// (only the array forms remain), every top-level free function moved under
/// `ModelUtilities` / `TextUtilities` / `TranscriptionUtilities`, `DecodingOptions`
/// lost `usePrefillCache` and fixed the `supressTokens` spelling, and callbacks are
/// now `@Sendable` — an error under Swift 6 mode, not a warning.
actor WhisperClient {
    /// Small enough to stay honest about download size next to Parakeet's 461 MB.
    static let defaultModel = "openai_whisper-base"

    private var pipeline: WhisperKit?

    var isLoaded: Bool { pipeline != nil }

    func load() async throws {
        guard pipeline == nil else { return }
        let started = Date()
        let config = WhisperKitConfig(model: Self.defaultModel, prewarm: true, load: true)
        pipeline = try await WhisperKit(config)
        log.info("whisper ready in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
    }

    func unload() {
        pipeline = nil
    }

    func transcribe(_ url: URL) async throws -> String {
        if pipeline == nil { try await load() }
        guard let pipeline else { return "" }

        let results = try await pipeline.transcribe(
            audioPath: url.path,
            decodeOptions: DecodingOptions(detectLanguage: true, chunkingStrategy: .vad)
        )
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
