//
//  TranscriptionModel.swift
//  UttCore
//

import Foundation

/// One model a transcription engine can run, and everything the UI needs to say
/// about it before you commit to the download.
///
/// `id` is the engine's own identifier, passed through untouched: FluidAudio names
/// its Parakeet bundles, WhisperKit names a folder in `argmaxinc/whisperkit-coreml`.
/// Nothing here translates between the two — a catalog that renames things is a
/// catalog you have to debug.
public struct TranscriptionModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let engine: TranscriptionEngine
    /// What the picker shows.
    public let name: String
    /// Languages, one line: "Multilingual", "English", "Japanese".
    public let languages: String
    /// Roughly what it weighs. Estimates, not promises — the numbers move when the
    /// upstream repos re-quantise, and the download UI says "about".
    public let approximateBytes: Int64

    public init(
        id: String,
        engine: TranscriptionEngine,
        name: String,
        languages: String,
        approximateBytes: Int64
    ) {
        self.id = id
        self.engine = engine
        self.name = name
        self.languages = languages
        self.approximateBytes = approximateBytes
    }

    /// "Multilingual · about 461 MB", for the row under the name. A fresh formatter
    /// per call — `ByteCountFormatter` is not `Sendable`, and one shared instance in
    /// a `static let` is a data race the compiler is right to refuse.
    public var summary: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return "\(languages) · about \(formatter.string(fromByteCount: approximateBytes))"
    }
}

/// The models utt offers, per engine.
///
/// Hand-written rather than fetched. Both engines *can* enumerate what their host
/// repo holds, but that is a network call on the way to a settings pane, it lists
/// dozens of quantisation variants nobody should have to choose between, and it
/// leaves the picker empty when offline. A short curated list is the feature.
public enum ModelCatalog {
    public static let all: [TranscriptionModel] = parakeet + whisper

    /// FluidAudio's `AsrModelVersion`, by its own name. Adding one here means adding
    /// the matching case to `ParakeetClient.version(for:)` — the compiler will not
    /// catch a typo, because these are strings on the wire.
    public static let parakeet: [TranscriptionModel] = [
        TranscriptionModel(
            id: "parakeet-v3",
            engine: .parakeet,
            name: "Parakeet TDT 0.6B v3",
            languages: "Multilingual",
            approximateBytes: 461_000_000
        ),
        TranscriptionModel(
            id: "parakeet-v2",
            engine: .parakeet,
            name: "Parakeet TDT 0.6B v2",
            languages: "English",
            approximateBytes: 461_000_000
        ),
        TranscriptionModel(
            id: "parakeet-tdt-ctc-110m",
            engine: .parakeet,
            name: "Parakeet TDT-CTC 110M",
            languages: "English, fastest",
            approximateBytes: 120_000_000
        ),
        TranscriptionModel(
            id: "parakeet-ja",
            engine: .parakeet,
            name: "Parakeet TDT 0.6B ja",
            languages: "Japanese",
            approximateBytes: 461_000_000
        )
    ]

    /// Folder names in `argmaxinc/whisperkit-coreml`, verified against the repo.
    /// WhisperKit takes these verbatim; a name that is not there fails at download
    /// time, not at compile time.
    public static let whisper: [TranscriptionModel] = [
        TranscriptionModel(
            id: "openai_whisper-tiny",
            engine: .whisper,
            name: "Whisper tiny",
            languages: "Multilingual, fastest",
            approximateBytes: 75_000_000
        ),
        TranscriptionModel(
            id: "openai_whisper-base",
            engine: .whisper,
            name: "Whisper base",
            languages: "Multilingual",
            approximateBytes: 145_000_000
        ),
        TranscriptionModel(
            id: "openai_whisper-small",
            engine: .whisper,
            name: "Whisper small",
            languages: "Multilingual",
            approximateBytes: 480_000_000
        ),
        TranscriptionModel(
            id: "openai_whisper-large-v3-v20240930_turbo",
            engine: .whisper,
            name: "Whisper large v3 turbo",
            languages: "Multilingual, most accurate",
            approximateBytes: 632_000_000
        )
    ]

    public static func models(for engine: TranscriptionEngine) -> [TranscriptionModel] {
        switch engine {
        case .parakeet: parakeet
        case .whisper: whisper
        }
    }

    /// First entry wins. The order above is the recommendation.
    public static func preferred(for engine: TranscriptionEngine) -> TranscriptionModel {
        guard let first = models(for: engine).first else {
            // Unreachable while both lists are non-empty, and a fatalError in a
            // settings pane is a worse bug than a wrong-looking picker.
            return TranscriptionModel(
                id: "", engine: engine, name: "None", languages: "—", approximateBytes: 0
            )
        }
        return first
    }

    /// The model an engine should actually load for a stored id.
    ///
    /// Falls back rather than failing, on purpose. A settings file can name a model
    /// from an older build, a different engine, or a typo — and the alternative to
    /// falling back is an app that cannot transcribe until you edit JSON.
    public static func resolve(
        id: String, engine: TranscriptionEngine
    ) -> TranscriptionModel {
        models(for: engine).first { $0.id == id } ?? preferred(for: engine)
    }
}
