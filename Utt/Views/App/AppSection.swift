import SwiftUI
import UttCore

/// Everything the rail can show: the history, then the settings pages. One enum
/// because it is one rail — a person moves from their transcripts to a setting
/// and back the same way they move between two settings.
///
/// An extension's page is a case like any other and carries its own manifest: the
/// rail cannot look up a title for a section that was declared by another process
/// after this enum was compiled.
enum AppSection: Hashable, Identifiable {
    case history
    case hotkey, microphone, model
    case replacements, cleanup, formatting
    case delivery, saving
    case sounds, permissions, general, about
    case api
    case extensions
    case `extension`(ExtensionManifest)

    var id: String {
        if case let .extension(manifest) = self { return "extension:\(manifest.id)" }
        return title
    }

    /// The rail, in reading order: the transcripts, then what starts a recording,
    /// what happens to the words, where they end up, the app around all of it, and
    /// how to reach it — and last whatever has connected itself to utt.
    ///
    /// Text is the pipeline in the order it runs. The rail is the only place that
    /// says a replacement fires before a cleanup and a cleanup before formatting,
    /// so its order is the documentation: a new stage slots in where it runs.
    static func groups(extensions: [ExtensionManifest]) -> [(title: String, sections: [AppSection])] {
        [
            ("", [.history]),
            ("Dictate", [.hotkey, .microphone, .model]),
            ("Text", [.replacements, .cleanup, .formatting]),
            ("Output", [.delivery, .saving]),
            ("App", [.sounds, .permissions, .general, .about]),
            ("Connect", [.api, .extensions] + extensions.map { .extension($0) })
        ]
    }

    var isSettings: Bool { self != .history }

    /// The section a `utt://show?section=…` names, or nil.
    ///
    /// Matched on a squashed id — case folded, everything but letters and digits
    /// dropped — so a caller writes `sounds` rather than `Sounds%20%26%20Indicator`.
    /// A prefix is enough, and an extension also answers to its bare id: the ids are
    /// the rail in reading order, and the first match wins, so `extensions` and
    /// `extension:deckhand` stay reachable while `deckhand` still lands.
    static func named(_ query: String, extensions: [ExtensionManifest]) -> AppSection? {
        let wanted = query.squashed
        guard !wanted.isEmpty else { return nil }
        let all = groups(extensions: extensions).flatMap(\.sections)
        return all.first { $0.id.squashed.hasPrefix(wanted) }
            ?? all.first {
                guard case let .extension(manifest) = $0 else { return false }
                return manifest.id.squashed.hasPrefix(wanted)
            }
            ?? retired[wanted]
    }

    /// Names the rail no longer has, pointed at the page that inherited them: one
    /// Text page became three stages, and "History" became "Saving" once the
    /// transcript list took that word. Last, so a live section always wins — and a
    /// name a script or an agent has already written keeps working.
    private static let retired: [String: AppSection] = ["text": .replacements, "history": .saving]

    var title: String {
        switch self {
        case .history: "Transcripts"
        case .hotkey: "Hotkey"
        case .microphone: "Microphone"
        case .model: "Model"
        case .replacements: "Replacements"
        case .cleanup: "Cleanup"
        case .formatting: "Formatting"
        case .delivery: "Delivery"
        case .saving: "Saving"
        case .sounds: "Sounds & Indicator"
        case .permissions: "Permissions"
        case .general: "General"
        case .about: "About"
        case .api: "API"
        case .extensions: "Extensions"
        case let .extension(manifest): manifest.name
        }
    }

    var systemImage: String {
        switch self {
        case .history: "text.quote"
        case .hotkey: "keyboard"
        case .microphone: "mic"
        case .model: "cpu"
        case .replacements: "arrow.left.arrow.right"
        case .cleanup: "wand.and.sparkles"
        case .formatting: "textformat"
        case .delivery: "text.cursor"
        case .saving: "clock.arrow.circlepath"
        case .sounds: "speaker.wave.2"
        case .permissions: "lock.shield"
        case .general: "gearshape"
        case .about: "info.circle"
        case .api: "network"
        case .extensions: "puzzlepiece.extension"
        case let .extension(manifest): manifest.systemImage ?? "puzzlepiece.extension"
        }
    }

    /// One line under the page title: what is on this page, for someone who
    /// arrived by scanning the rail.
    var blurb: String {
        switch self {
        case .history: "Everything you have said, newest first."
        case .hotkey: "The key you hold to talk, and how a press is read."
        case .microphone: "Which input utt listens to, and what happens around it while it does."
        case .model: "The engine and the model doing the transcribing. Everything runs on this Mac."
        case .replacements: "Words utt swaps out first, and a bench that shows the whole pipeline working."
        case .cleanup: "The pass that takes out what you did not mean to say."
        case .formatting: "The last word on case and punctuation, after everything else has run."
        case .delivery: "Where a transcript goes when you let go of the key."
        case .saving: "What utt keeps of what you said."
        case .sounds: "What you hear and see while a recording is running."
        case .permissions: "What macOS has to allow before utt can hear you and type for you."
        case .general: "How utt sits in the system."
        case .about: "Version, updates and who made the models."
        case .api: "Let another app or device send audio to this Mac and get text back."
        case .extensions: "Programs that work with utt. Each one keeps its settings here, next to utt's own."
        case let .extension(manifest): manifest.blurb ?? "Settings for \(manifest.name). Changed here, read by \(manifest.name)."
        }
    }
}

private extension String {
    /// Case folded, letters and digits only. `"Sounds & Indicator"` →
    /// `"soundsindicator"`, `"extension:deckhand"` → `"extensiondeckhand"`.
    var squashed: String { lowercased().filter { $0.isLetter || $0.isNumber } }
}
