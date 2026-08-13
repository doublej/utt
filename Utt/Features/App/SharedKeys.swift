import ComposableArchitecture
import Foundation
import UttCore

extension SharedKey where Self == FileStorageKey<UttSettings>.Default {
    /// The one settings instance every feature reads and writes.
    ///
    /// File-backed rather than `.appStorage`: settings hold arrays (word
    /// removals, remappings) that UserDefaults would flatten, and a JSON file
    /// under Application Support is something a person can open and edit — which
    /// is exactly what `UttSettings`' forgiving decoder is built for.
    static var uttSettings: Self {
        // The URL accessor throws only if Application Support cannot be created;
        // at that point there is no usable app, so a temp file is the honest
        // fallback rather than a crash on launch.
        let url = (try? URL.uttSettingsFile)
            ?? URL.temporaryDirectory.appending(path: "utt-settings.json")
        return Self[.fileStorage(url), default: UttSettings()]
    }
}

extension SharedKey where Self == FileStorageKey<TranscriptionHistory>.Default {
    /// Past transcripts, in their own file so a corrupt history can never take
    /// settings down with it.
    static var uttHistory: Self {
        let url = (try? URL.uttHistoryFile)
            ?? URL.temporaryDirectory.appending(path: "utt-history.json")
        return Self[.fileStorage(url), default: TranscriptionHistory()]
    }
}
