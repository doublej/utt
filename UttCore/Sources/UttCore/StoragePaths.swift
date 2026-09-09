import Foundation

public extension URL {
    /// `~/Library/Application Support/dev.jurrejan.utt`, created on first access.
    /// utt is not sandboxed, so this is the real path, not a container.
    static var uttApplicationSupport: URL {
        get throws {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = appSupport.appendingPathComponent(UttLog.subsystem, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    /// Where `UttSettings` is persisted.
    static var uttSettingsFile: URL {
        get throws { try uttApplicationSupport.appending(component: "settings.json") }
    }

    /// Where `TranscriptionHistory` is persisted.
    static var uttHistoryFile: URL {
        get throws { try uttApplicationSupport.appending(component: "history.json") }
    }

    /// The input devices utt can currently see, exported for other processes —
    /// the Raycast extension needs CoreAudio UIDs to write `microphonePriority`,
    /// and nothing outside a CoreAudio client can enumerate them.
    static var uttDevicesFile: URL {
        get throws { try uttApplicationSupport.appending(component: "devices.json") }
    }

    /// Where plugins declare themselves. Created eagerly rather than on demand:
    /// a plugin cannot drop a manifest into a directory that does not exist yet,
    /// and it has no way to know whether utt has ever run.
    static var uttPluginsDirectory: URL {
        get throws {
            let directory = try uttApplicationSupport
                .appendingPathComponent("plugins", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    /// Downloaded transcription model bundles.
    static var uttModelsDirectory: URL {
        get throws {
            let directory = try uttApplicationSupport.appendingPathComponent("models", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    /// FluidAudio's own cache. It writes to `<Application Support>/FluidAudio/Models`
    /// no matter what `XDG_CACHE_HOME` says, so "Show in Finder" has to point here
    /// rather than at `uttModelsDirectory`.
    static var fluidAudioModelsDirectory: URL {
        get throws {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = appSupport.appendingPathComponent("FluidAudio/Models", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    /// Scratch space for in-flight recordings. Cleared on launch — a wav here is
    /// either being written right now or was orphaned by a crash.
    static var uttRecordings: URL {
        get throws {
            let directory = try uttApplicationSupport
                .appendingPathComponent("recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }
}
