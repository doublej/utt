import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "transcription")

/// Dispatches to whichever engine the user selected. Parakeet is the default and
/// the only one that needs to be fast; WhisperKit is there for languages and clips
/// Parakeet handles poorly.
@DependencyClient
struct TranscriptionClient: Sendable {
    /// `model` is the engine's own identifier — see `ModelCatalog`. It travels with
    /// every call rather than being set once: the engines are long-lived actors, and
    /// a mode they have to be *told* about drifts out of step with the setting.
    var transcribe: @Sendable (
        _ url: URL, _ engine: TranscriptionEngine, _ model: String
    ) async throws -> String
    /// Download + load, so the first hotkey press is not a 26-second stall.
    var prewarm: @Sendable (_ engine: TranscriptionEngine, _ model: String) async throws -> Void
    var isReady: @Sendable (
        _ engine: TranscriptionEngine, _ model: String
    ) async -> Bool = { _, _ in false }
    var unload: @Sendable () async -> Void
}

extension TranscriptionClient: DependencyKey {
    static let liveValue: TranscriptionClient = {
        let parakeet = ParakeetClient()
        let whisper = WhisperClient()
        return TranscriptionClient(
            transcribe: { url, engine, model in
                switch engine {
                case .parakeet:
                    let result = try await parakeet.transcribe(url, model: model)
                    log.info("""
                        parakeet: \(result.duration, format: .fixed(precision: 1))s clip, \
                        rtfx \(result.realtimeFactor, format: .fixed(precision: 1))x, \
                        confidence \(result.confidence, format: .fixed(precision: 2))
                        """)
                    return result.text
                case .whisper:
                    return try await whisper.transcribe(url, model: model)
                }
            },
            prewarm: { engine, model in
                switch engine {
                case .parakeet: try await parakeet.load(model)
                case .whisper: try await whisper.load(model)
                }
            },
            isReady: { engine, model in
                switch engine {
                case .parakeet: await parakeet.isLoaded(model)
                case .whisper: await whisper.isLoaded(model)
                }
            },
            unload: {
                await parakeet.unload()
                await whisper.unload()
            }
        )
    }()
}

extension DependencyValues {
    var transcription: TranscriptionClient {
        get { self[TranscriptionClient.self] }
        set { self[TranscriptionClient.self] = newValue }
    }
}
