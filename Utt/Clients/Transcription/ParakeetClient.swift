import Dependencies
import FluidAudio
import Foundation
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "parakeet")

/// On-device Parakeet TDT v3 via FluidAudio.
///
/// Deliberately not ported from the reference app: its `ParakeetClient` does
/// four-root × two-casing cache archaeology to find models, which exists only because
/// it is sandboxed. We are not, so FluidAudio's default cache location just works.
actor ParakeetClient {
    /// FluidAudio rejects clips shorter than this outright (`ASRError.invalidAudioData`).
    /// Note this is **0.3 s**, not the 1.5 s the reference app pads to — anything from
    /// 0.3 s to 15 s is zero-padded internally by the decoder, so padding above 0.3 s
    /// is wasted work that stretches every short utterance.
    static let minimumDuration: TimeInterval = 0.3

    /// Roughly what the v3 model weighs on disk, for progress estimation.
    /// The reference app hardcodes 650 MB, so its bar stalls near 69% and then snaps to 100.
    static let approximateDownloadBytes: Int64 = 461_000_000

    private var manager: AsrManager?
    /// What `manager` was built from, so a model change is detectable. Without it a
    /// switch in Settings silently keeps transcribing on the old weights.
    private var loadedModel: String?
    /// The load already in flight — see `WhisperClient.loading` for why an actor
    /// alone does not make two overlapping loads safe.
    private var loading: Task<Void, Error>?

    var isLoaded: Bool { manager != nil }

    func isLoaded(_ model: String) -> Bool { manager != nil && loadedModel == model }

    /// FluidAudio's own enum. String ids come from `ModelCatalog`, which is where a
    /// new entry has to be added first — an unknown id lands on v3 rather than
    /// throwing, matching how the catalog resolves an unknown stored setting.
    private static func version(for model: String) -> AsrModelVersion {
        switch model {
        case "parakeet-v2": .v2
        case "parakeet-tdt-ctc-110m": .tdtCtc110m
        case "parakeet-ja": .tdtJa
        default: .v3
        }
    }

    /// Whether the weights are already in FluidAudio's cache. Its own check, not a
    /// folder test: an interrupted download leaves the directory behind with half
    /// the files in it, and `modelsExist` looks for every one this version needs.
    ///
    /// `static`, so it is not actor-isolated and the settings pane can ask about
    /// every model in the catalog while drawing a row.
    static func isDownloaded(_ model: String) -> Bool {
        let version = version(for: model)
        return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)
    }

    /// FluidAudio counts files, not bytes, and compiles once the download lands.
    private static func phase(_ progress: DownloadProgress) -> ModelPreparation {
        switch progress.phase {
        case .listing: .downloading(fraction: 0)
        case .downloading: .downloading(fraction: progress.fractionCompleted)
        case .compiling: .loading
        }
    }

    /// Downloads if needed, then loads. The first load after install pays a one-time
    /// ~27 s ANE compile of the encoder *on top of* the download, so any "ready in N
    /// seconds" estimate computed from bytes alone will be wrong — which is why the
    /// two phases are reported separately rather than as one percentage.
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
        guard loadedModel != model || manager == nil else { return }
        let started = Date()
        let models = try await AsrModels.downloadAndLoad(version: Self.version(for: model)) { progress in
            onProgress(Self.phase(progress))
        }
        // Nothing is downloaded from here on, whatever the last progress event said.
        onProgress(.loading)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        loadedModel = model
        log.info("parakeet \(model) ready in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
    }

    func unload() {
        manager = nil
        loadedModel = nil
    }

    struct Transcript: Sendable {
        let text: String
        let confidence: Float
        let duration: TimeInterval
        /// Realtime factor — 23× on a 3 s clip, 51× on a 6.6 s clip, measured.
        let realtimeFactor: Float
    }

    func transcribe(_ url: URL, model: String) async throws -> Transcript {
        try await load(model)
        guard let manager else { throw ASRError.modelLoadFailed }

        // `TdtDecoderState` is passed `inout` to an async call, so it must be a local
        // var in a *nonisolated-from-MainActor* context. A stored property — or a
        // local in main-actor-isolated code — fails to compile with "actor-isolated
        // var cannot be passed 'inout' to 'async' function call".
        var state = await TdtDecoderState.make(decoderLayers: manager.decoderLayerCount)
        let result = try await manager.transcribe(url, decoderState: &state)

        return Transcript(
            text: result.text,
            confidence: result.confidence,
            duration: result.duration,
            realtimeFactor: result.rtfx
        )
    }
}
