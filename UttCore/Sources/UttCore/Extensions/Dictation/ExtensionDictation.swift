//
//  ExtensionDictation.swift
//  UttCore
//
//  A dictation an extension started for itself with `utt://start?for=<id>`, and
//  the one file utt writes only for that: the level its own meter is drawn from.
//

import Foundation

/// The extension a dictation belongs to. It draws the recording itself, so utt
/// shows none of its own panels, pastes nothing, and hands the words to it alone.
public struct DictationOwner: Equatable, Sendable {
    public let id: String
    /// What the history entry and the transcript's `app` say received the words.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// The id a `utt://start?for=<id>` names, or nil for an ordinary start. Only
    /// the shape is checked here; whether that extension may have it is the store's
    /// question, asked against what the person approved.
    public static func requested(by url: URL) -> String? {
        let named = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "for" }?.value
        return named.flatMap { ExtensionManifest.isSafeIdentifier($0) ? $0 : nil }
    }

    /// Whether this extension may start dictations of its own: approved, and
    /// declaring both the capability and the transcripts the words arrive in.
    public static func allows(_ manifest: ExtensionManifest, approved: Bool) -> Bool {
        approved && manifest.ownsDictation && manifest.wantsTranscripts
    }
}

/// `<id>.level.json`: the microphone's level during a dictation the extension
/// started, about twenty times a second, so it can draw its own meter.
public struct ExtensionLevel: Codable, Equatable, Sendable {
    /// Increments on every write, the closing one included, across recordings.
    public var sequence: Int
    /// Peak amplitude, 0...1, linear. utt's own meters draw it on a dB scale
    /// floored at -60, because speech sits in the bottom few percent of a linear one.
    public var level: Double
    /// False on exactly one write per recording: the microphone has closed.
    public var recording: Bool
    /// The name of the model that will write the transcript, as utt's picker shows it.
    public var model: String?

    public init(sequence: Int, level: Double, recording: Bool, model: String? = nil) {
        self.sequence = sequence
        self.level = level
        self.recording = recording
        self.model = model
    }
}
