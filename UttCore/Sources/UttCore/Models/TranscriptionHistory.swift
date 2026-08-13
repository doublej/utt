//
//  TranscriptionHistory.swift
//  UttCore
//

import Foundation

/// One finished transcription plus the audio it came from.
///
/// `timestamp` is always supplied by the caller — core logic reads the clock through
/// `@Dependency(\.date.now)`, never `Date()`.
public struct Transcript: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var text: String
    /// The captured audio, when it was kept. Nil is the normal case: 16 kHz mono
    /// PCM runs ~32 KB/s, so retaining every clip would make the unlimited default
    /// for `maxHistoryEntries` a disk leak. Text is what history is for.
    public var audioPath: URL?
    public var duration: TimeInterval
    public var sourceAppBundleID: String?
    public var sourceAppName: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        text: String,
        audioPath: URL? = nil,
        duration: TimeInterval,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.audioPath = audioPath
        self.duration = duration
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
    }
}

public struct TranscriptionHistory: Codable, Equatable, Sendable {
    /// Newest first — the list is read far more often than it is appended to, and
    /// every reader wants the most recent transcript.
    public var history: [Transcript] = []

    public init(history: [Transcript] = []) {
        self.history = history
    }

    /// Inserts at the front and trims to `cap`. A nil cap keeps everything, which is
    /// affordable because entries are text only.
    public mutating func record(_ transcript: Transcript, cap: Int?) {
        history.insert(transcript, at: 0)
        guard let cap else { return }
        // A cap of zero means "keep no history", not "keep one".
        guard cap > 0 else { return history.removeAll() }
        if history.count > cap { history.removeLast(history.count - cap) }
    }

    public mutating func remove(_ id: Transcript.ID) {
        history.removeAll { $0.id == id }
    }
}
