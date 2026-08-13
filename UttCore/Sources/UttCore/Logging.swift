import os.log

/// Shared `os.Logger` factory so every subsystem string in the app and in
/// UttCore is the same one — a single `log stream --subsystem dev.jurrejan.utt`
/// then shows the whole recording pipeline.
public enum UttLog {
    public static let subsystem = "dev.jurrejan.utt"

    public enum Category: String {
        case app = "App"
        case caches = "Caches"
        case history = "History"
        case hotKey = "HotKey"
        case keyEvent = "KeyEvent"
        case media = "Media"
        case migration = "Migration"
        case models = "Models"
        case parakeet = "Parakeet"
        case pasteboard = "Pasteboard"
        case permissions = "Permissions"
        case recording = "Recording"
        case settings = "Settings"
        case sound = "SoundEffect"
        case transcription = "Transcription"
    }

    public static func logger(_ category: Category) -> os.Logger {
        os.Logger(subsystem: subsystem, category: category.rawValue)
    }

    public static let app = logger(.app)
    public static let caches = logger(.caches)
    public static let history = logger(.history)
    public static let hotKey = logger(.hotKey)
    public static let keyEvent = logger(.keyEvent)
    public static let media = logger(.media)
    public static let migration = logger(.migration)
    public static let models = logger(.models)
    public static let parakeet = logger(.parakeet)
    public static let pasteboard = logger(.pasteboard)
    public static let permissions = logger(.permissions)
    public static let recording = logger(.recording)
    public static let settings = logger(.settings)
    public static let sound = logger(.sound)
    public static let transcription = logger(.transcription)
}
