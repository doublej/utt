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
    var transcribe: @Sendable (_ url: URL, _ engine: TranscriptionEngine) async throws -> String
    /// Download + load, so the first hotkey press is not a 26-second stall.
    var prewarm: @Sendable (_ engine: TranscriptionEngine) async throws -> Void
    var isReady: @Sendable (_ engine: TranscriptionEngine) async -> Bool = { _ in false }
    var unload: @Sendable () async -> Void
}

extension TranscriptionClient: DependencyKey {
    static let liveValue: TranscriptionClient = {
        let parakeet = ParakeetClient()
        let whisper = WhisperClient()
        return TranscriptionClient(
            transcribe: { url, engine in
                switch engine {
                case .parakeet:
                    let result = try await parakeet.transcribe(url)
                    log.info("""
                        parakeet: \(result.duration, format: .fixed(precision: 1))s clip, \
                        rtfx \(result.realtimeFactor, format: .fixed(precision: 1))x, \
                        confidence \(result.confidence, format: .fixed(precision: 2))
                        """)
                    return result.text
                case .whisper:
                    return try await whisper.transcribe(url)
                }
            },
            prewarm: { engine in
                switch engine {
                case .parakeet: try await parakeet.load()
                case .whisper: try await whisper.load()
                }
            },
            isReady: { engine in
                switch engine {
                case .parakeet: await parakeet.isLoaded
                case .whisper: await whisper.isLoaded
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
