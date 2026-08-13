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

    /// Downloads if needed, then loads. The first load after install pays a one-time
    /// ~27 s ANE compile of the encoder *on top of* the download, so any "ready in N
    /// seconds" estimate computed from bytes alone will be wrong.
    func load(_ model: String) async throws {
        guard loadedModel != model || manager == nil else { return }
        let started = Date()
        let models = try await AsrModels.downloadAndLoad(version: Self.version(for: model))
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
