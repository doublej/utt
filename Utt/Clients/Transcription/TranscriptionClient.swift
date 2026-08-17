import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "transcription")

/// What getting a model ready looks like from the outside. Two phases, because
/// they fail differently and take differently long: the download is bytes over
/// the network and knows its own fraction; the CoreML compile and load that
/// follows is a one-time ~27 s of ANE work that reports nothing at all.
enum ModelPreparation: Equatable, Sendable {
    case downloading(fraction: Double)
    case loading
}

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
    /// Download + load, so the first hotkey press is not a 26-second stall. The
    /// stream reports phases and finishes when the model is loaded — or when it
    /// gave up, which `isReady` is there to tell apart.
    var prepare: @Sendable (
        _ engine: TranscriptionEngine, _ model: String
    ) -> AsyncStream<ModelPreparation> = { _, _ in .finished }
    /// Already on disk, answered without touching the network. Synchronous because
    /// the picker asks it of every model it draws.
    var isDownloaded: @Sendable (
        _ engine: TranscriptionEngine, _ model: String
    ) -> Bool = { _, _ in false }
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
            // The engines report progress through a callback on an unspecified
            // queue; a continuation is the one bridge to the store that does not
            // need that queue to be the main one.
            prepare: { engine, model in
                AsyncStream { continuation in
                    let task = Task {
                        do {
                            switch engine {
                            case .parakeet:
                                try await parakeet.load(model) { continuation.yield($0) }
                            case .whisper:
                                try await whisper.load(model) { continuation.yield($0) }
                            }
                        } catch {
                            log.error("\(model, privacy: .public): \(error.localizedDescription)")
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            isDownloaded: { engine, model in
                switch engine {
                case .parakeet: ParakeetClient.isDownloaded(model)
                case .whisper: WhisperClient.isDownloaded(model)
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
