//
//  ExtensionLog.swift
//  UttCore
//
//  What utt did with an extension, kept where the person can read it.
//

import Dependencies
import Foundation
import Synchronization
import os

/// One thing utt decided about an extension, in utt's own words.
///
/// Everything here was already being said to the unified log, which is where it
/// stayed: `log stream` is not something an extension author thinks to run, and
/// `log show` cannot even open the store from an ordinary shell. So a manifest
/// with a refused key, a clip that failed and a filter that never answered all
/// looked the same from outside — nothing happened, and no evidence anywhere.
public struct ExtensionLogEntry: Equatable, Identifiable, Sendable {
    public enum Level: String, Sendable {
        /// Something happened. utt is working.
        case note
        /// Something utt refused, dropped or could not do. The page tints these.
        case problem
    }

    public let id: UUID
    /// The extension it is about, or nil for a manifest utt could not attribute —
    /// a file it could not read, or one whose id disagrees with its filename.
    /// That is exactly the case with no page of its own to be read on, which is
    /// why the extensions list shows the whole log rather than only per-extension.
    public let extensionID: String?
    public let level: Level
    public let message: String
    /// The last time it happened, not the first: a standing problem is current news.
    public var timestamp: Date
    /// How often this same line has been said. See `ExtensionLogBook.record`.
    public var count: Int

    public init(
        id: UUID = UUID(), extensionID: String?, level: Level, message: String,
        timestamp: Date, count: Int = 1
    ) {
        self.id = id
        self.extensionID = extensionID
        self.level = level
        self.message = message
        self.timestamp = timestamp
        self.count = count
    }
}

/// The entries, newest first, bounded.
public struct ExtensionLogBook: Equatable, Sendable {
    /// Enough to hold a session's worth of a busy extension without becoming a
    /// thing that has to be paged through.
    public static let capacity = 200

    public private(set) var entries: [ExtensionLogEntry] = []

    public init() {}

    /// Records an entry and says whether it is one utt has not seen before.
    ///
    /// The same message about the same extension is the same entry said again: its
    /// count goes up, its time moves and it returns to the front. Manifests are
    /// re-read three times a second, so without this one refused key is the entire
    /// log within a minute — and a log that scrolls a standing problem off itself
    /// is a log that hides it.
    @discardableResult
    public mutating func record(_ entry: ExtensionLogEntry) -> Bool {
        if let index = entries.firstIndex(where: {
            $0.extensionID == entry.extensionID && $0.message == entry.message
        }) {
            var repeated = entries.remove(at: index)
            repeated.timestamp = entry.timestamp
            repeated.count += 1
            entries.insert(repeated, at: 0)
            return false
        }
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        return true
    }

    public func entries(about extensionID: String) -> [ExtensionLogEntry] {
        entries.filter { $0.extensionID == extensionID }
    }
}

/// The one sink. Every lane writes here instead of to its own `Logger`, and the
/// unified log still gets each line — once, the first time it is said.
///
/// In memory, and not persisted on purpose. A log on disk would need trimming,
/// migrating and owner-only permissions, and the entries worth reading are
/// standing ones: a refused key, a daemon that will not start and a filter that
/// never answers are all said again within three seconds of the next launch.
public enum ExtensionLog {
    private static let book = Mutex(ExtensionLogBook())
    private static let logger = Logger(subsystem: UttLog.subsystem, category: "extensions")

    /// utt working: a clip transcribed, a decision carried over.
    public static func note(_ extensionID: String?, _ message: String) {
        record(.note, extensionID, message)
    }

    /// utt refusing, dropping, or failing at something the extension asked for.
    public static func problem(_ extensionID: String?, _ message: String) {
        record(.problem, extensionID, message)
    }

    public static var entries: [ExtensionLogEntry] {
        book.withLock { $0.entries }
    }

    public static func entries(about extensionID: String) -> [ExtensionLogEntry] {
        book.withLock { $0.entries(about: extensionID) }
    }

    private static func record(_ level: ExtensionLogEntry.Level, _ id: String?, _ message: String) {
        @Dependency(\.date.now) var now
        let isNew = book.withLock {
            $0.record(ExtensionLogEntry(extensionID: id, level: level, message: message, timestamp: now))
        }
        // Only the first time. The mirror is what floods otherwise: the poll that
        // notices a refused key runs three times a second, forever.
        guard isNew else { return }
        let line = "\(id ?? "extensions"): \(message)"
        switch level {
        case .note: logger.notice("\(line, privacy: .public)")
        case .problem: logger.error("\(line, privacy: .public)")
        }
    }
}
