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
    /// One sentence on what it is for, under the summary.
    public let blurb: String
    public let ratings: ModelRatings

    public init(
        id: String,
        engine: TranscriptionEngine,
        name: String,
        languages: String,
        approximateBytes: Int64,
        blurb: String,
        ratings: ModelRatings
    ) {
        self.id = id
        self.engine = engine
        self.name = name
        self.languages = languages
        self.approximateBytes = approximateBytes
        self.blurb = blurb
        self.ratings = ratings
    }

    /// "Multilingual, 461 MB", beside the ratings. A fresh formatter
    /// per call — `ByteCountFormatter` is not `Sendable`, and one shared instance in
    /// a `static let` is a data race the compiler is right to refuse.
    public var summary: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return "\(languages), \(formatter.string(fromByteCount: approximateBytes))"
    }
}

/// What a model is good at, each facet scored 1–4 across *every* model in the
/// catalog, both engines — so a row can be compared with any other row.
///
/// More is always better, which is why the size facet is `lightness` rather than
/// `size`. Judged from FluidAudio's release benchmarks (LibriSpeech, FLEURS, RTFx
/// on the Neural Engine) and a smoke run on one dictation clip, not measured here.
public struct ModelRatings: Equatable, Sendable {
    public static let scale = 4

    public let speed: Int
    public let accuracy: Int
    /// 1 for one language, 3 for Parakeet's 25 European, 4 for Whisper's ~100.
    public let languages: Int
    /// 4 under ~150 MB, 3 under ~400 MB, 2 under ~500 MB, 1 above.
    public let lightness: Int

    public init(speed: Int, accuracy: Int, languages: Int, lightness: Int) {
        self.speed = speed
        self.accuracy = accuracy
        self.languages = languages
        self.lightness = lightness
    }

    public subscript(facet: ModelFacet) -> Int {
        switch facet {
        case .speed: speed
        case .accuracy: accuracy
        case .languages: languages
        case .lightness: lightness
        }
    }
}

public enum ModelFacet: String, CaseIterable, Sendable, Identifiable {
    case speed, accuracy, languages, lightness

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .speed: "Speed"
        case .accuracy: "Accuracy"
        case .languages: "Languages"
        case .lightness: "Light"
        }
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
            name: "Parakeet Standard",
            languages: "Multilingual",
            approximateBytes: 461_000_000,
            blurb: "NVIDIA's Parakeet v3. 25 European languages, detected on their own.",
            ratings: ModelRatings(speed: 3, accuracy: 3, languages: 3, lightness: 2)
        ),
        TranscriptionModel(
            id: "parakeet-ultra",
            engine: .parakeet,
            name: "Parakeet Ultra",
            languages: "Multilingual",
            approximateBytes: 632_000_000,
            blurb: "Moondream's retrain of Parakeet Standard. Fewer errors in every language, as fast, heavier.",
            ratings: ModelRatings(speed: 3, accuracy: 4, languages: 3, lightness: 1)
        ),
        TranscriptionModel(
            id: "parakeet-redux",
            engine: .parakeet,
            name: "Parakeet Redux",
            languages: "Multilingual",
            approximateBytes: 220_000_000,
            blurb: "Moondream's Parakeet Standard at a third of the size. Slower, worse in noise; the first load compiles for about ten minutes.",
            ratings: ModelRatings(speed: 2, accuracy: 2, languages: 3, lightness: 3)
        ),
        TranscriptionModel(
            id: "parakeet-phonon2",
            engine: .parakeet,
            name: "Phonon-2",
            languages: "English",
            approximateBytes: 360_000_000,
            blurb: "Fermion Research's English-only Parakeet Standard. Lighter, and the tidiest punctuation on our test clip.",
            ratings: ModelRatings(speed: 3, accuracy: 3, languages: 1, lightness: 3)
        ),
        TranscriptionModel(
            id: "parakeet-bark3-clean",
            engine: .parakeet,
            name: "Bark Clean",
            languages: "English",
            approximateBytes: 447_000_000,
            blurb: "Conway Research's Underdog Bark 3.0 Clean, an English Parakeet that drops the ums, false starts and repeats as it hears them.",
            ratings: ModelRatings(speed: 3, accuracy: 3, languages: 1, lightness: 2)
        ),
        TranscriptionModel(
            id: "parakeet-bark3",
            engine: .parakeet,
            name: "Bark Verbatim",
            languages: "English",
            approximateBytes: 436_000_000,
            blurb: "Conway Research's Underdog Bark 3.0, an English Parakeet that keeps every um and repeat. Strongest on meetings.",
            ratings: ModelRatings(speed: 3, accuracy: 3, languages: 1, lightness: 2)
        ),
        TranscriptionModel(
            id: "parakeet-v2",
            engine: .parakeet,
            name: "Parakeet English Classic",
            languages: "English",
            approximateBytes: 461_000_000,
            blurb: "NVIDIA's Parakeet v2, Standard's English-only predecessor.",
            ratings: ModelRatings(speed: 3, accuracy: 3, languages: 1, lightness: 2)
        ),
        TranscriptionModel(
            id: "parakeet-tdt-ctc-110m",
            engine: .parakeet,
            name: "Parakeet Quick",
            languages: "English",
            approximateBytes: 120_000_000,
            blurb: "Parakeet 110M, a fifth of Standard's size. Near-instant, and it shows on hard words.",
            ratings: ModelRatings(speed: 4, accuracy: 2, languages: 1, lightness: 4)
        ),
        TranscriptionModel(
            id: "parakeet-ja",
            engine: .parakeet,
            name: "Parakeet Japanese",
            languages: "Japanese",
            approximateBytes: 461_000_000,
            blurb: "NVIDIA's Parakeet ja, trained for Japanese only.",
            ratings: ModelRatings(speed: 3, accuracy: 3, languages: 1, lightness: 2)
        )
    ]

    /// Folder names in `argmaxinc/whisperkit-coreml`, verified against the repo.
    /// WhisperKit takes these verbatim; a name that is not there fails at download
    /// time, not at compile time.
    public static let whisper: [TranscriptionModel] = [
        TranscriptionModel(
            id: "openai_whisper-tiny",
            engine: .whisper,
            name: "Whisper Quick",
            languages: "Multilingual",
            approximateBytes: 75_000_000,
            blurb: "OpenAI's Whisper tiny. Quick to fetch, rough on anything but clear speech.",
            ratings: ModelRatings(speed: 4, accuracy: 1, languages: 4, lightness: 4)
        ),
        TranscriptionModel(
            id: "openai_whisper-base",
            engine: .whisper,
            name: "Whisper Light",
            languages: "Multilingual",
            approximateBytes: 145_000_000,
            blurb: "Whisper base. A step up from Quick, still a sketch of what you said.",
            ratings: ModelRatings(speed: 3, accuracy: 1, languages: 4, lightness: 4)
        ),
        TranscriptionModel(
            id: "openai_whisper-small",
            engine: .whisper,
            name: "Whisper Standard",
            languages: "Multilingual",
            approximateBytes: 480_000_000,
            blurb: "Whisper small. Usable in most languages, at Parakeet's size and well below its speed.",
            ratings: ModelRatings(speed: 2, accuracy: 2, languages: 4, lightness: 2)
        ),
        TranscriptionModel(
            id: "openai_whisper-large-v3-v20240930_turbo",
            engine: .whisper,
            name: "Whisper Accurate",
            languages: "Multilingual",
            approximateBytes: 632_000_000,
            blurb: "Whisper large v3 turbo. The one for a language Parakeet does not know.",
            ratings: ModelRatings(speed: 1, accuracy: 3, languages: 4, lightness: 1)
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
                id: "", engine: engine, name: "None", languages: "—", approximateBytes: 0,
                blurb: "", ratings: ModelRatings(speed: 0, accuracy: 0, languages: 0, lightness: 0)
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
