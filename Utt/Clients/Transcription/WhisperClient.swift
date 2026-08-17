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
    private var pipeline: WhisperKit?
    /// What `pipeline` was built from. A model change has to rebuild it — WhisperKit
    /// holds the weights, so keeping the old pipeline keeps the old model.
    private var loadedModel: String?
    /// The load already in flight. An actor is not a lock: two `load` calls suspend
    /// at the same `await` and *both* build a pipeline, so whichever finishes last
    /// wins — pick base while tiny is still compiling and the app ends up holding
    /// tiny while the UI asks about base and is told it failed to load. Chaining
    /// each load onto the previous one makes the last caller the winner.
    /// Unstructured on purpose: the caller's cancellation must not abandon a load
    /// half-way through assigning `pipeline`.
    private var loading: Task<Void, Error>?

    var isLoaded: Bool { pipeline != nil }

    func isLoaded(_ model: String) -> Bool { pipeline != nil && loadedModel == model }

    /// Where `HubApi` puts `argmaxinc/whisperkit-coreml`. Recomputed rather than
    /// asked, because the type that knows it lives in the `ArgmaxCore` module and
    /// we depend on the `WhisperKit` product; the layout is stable and checked
    /// against a real download.
    private static func localFolder(_ model: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appending(path: "huggingface/models/argmaxinc/whisperkit-coreml/\(model)")
    }

    /// The three model files a variant cannot run without. A folder test alone
    /// would call an interrupted download a finished one.
    ///
    /// `static`, so it is not actor-isolated and the settings pane can ask about
    /// every model in the catalog while drawing a row.
    static func isDownloaded(_ model: String) -> Bool {
        guard let folder = localFolder(model) else { return false }
        return ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
            .allSatisfy {
                FileManager.default.fileExists(
                    atPath: folder.appending(path: $0).path(percentEncoded: false)
                )
            }
    }

    /// `model` is a folder name in `argmaxinc/whisperkit-coreml`, passed through
    /// untouched. WhisperKit downloads it on demand and throws if it does not exist.
    ///
    /// Downloading explicitly rather than letting `WhisperKitConfig` do it buys two
    /// things: a real percentage, and a load that never touches the network once the
    /// weights are on disk — `WhisperKit.download` lists the remote repo on every
    /// call, so the config path fails offline even for a model already downloaded.
    func load(
        _ model: String,
        onProgress: @escaping @Sendable (ModelPreparation) -> Void = { _ in }
    ) async throws {
        let previous = loading
        let task = Task {
            _ = await previous?.result
            try await loadNow(model, onProgress: onProgress)
        }
        loading = task
        try await task.value
    }

    private func loadNow(
        _ model: String,
        onProgress: @escaping @Sendable (ModelPreparation) -> Void
    ) async throws {
        guard loadedModel != model || pipeline == nil else { return }
        let started = Date()
        let folder: URL?
        if Self.isDownloaded(model) {
            folder = Self.localFolder(model)
        } else {
            folder = try await WhisperKit.download(variant: model) { progress in
                onProgress(.downloading(fraction: progress.fractionCompleted))
            }
        }
        onProgress(.loading)
        let config = WhisperKitConfig(
            model: model,
            modelFolder: folder?.path(percentEncoded: false),
            prewarm: true,
            load: true
        )
        pipeline = try await WhisperKit(config)
        loadedModel = model
        log.info("whisper \(model) ready in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
    }

    func unload() {
        pipeline = nil
        loadedModel = nil
    }

    func transcribe(_ url: URL, model: String) async throws -> String {
        try await load(model)
        guard let pipeline else { return "" }

        let results = try await pipeline.transcribe(
            audioPath: url.path,
            decodeOptions: DecodingOptions(detectLanguage: true, chunkingStrategy: .vad)
        )
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
