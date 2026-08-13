import Foundation
import Observation
import UttCore

/// Holds the overlay's look, and in preview mode keeps it in step with the file on
/// disk so you can tune the glow with the indicator pinned on screen beside the
/// editor.
///
/// Polling beats a file-descriptor watcher here: editors save by writing a new file
/// and renaming it over the old one, which leaves an `DispatchSource` watching a
/// descriptor that no longer has a name. Modification date is immune to that.
///
/// Only polls while pinned. Shipping builds read the file once at launch — a timer
/// stat-ing a file forever to catch an edit nobody is making is pure waste.
@MainActor
@Observable
final class OverlayStyleStore {
    static let shared = OverlayStyleStore()

    private(set) var style = OverlayStyle.loaded()

    private var modifiedAt: Date?
    private var timer: Timer?

    /// True when `UTT_OVERLAY_DEBUG` pins the overlay on for tuning.
    static var isPreviewing: Bool {
        ProcessInfo.processInfo.environment["UTT_OVERLAY_DEBUG"] != nil
    }

    private init() {
        guard Self.isPreviewing else { return }
        // Seed the file with the current defaults so there is something to edit, and
        // so the list of knobs comes from the struct rather than from a copy in the
        // justfile that goes stale the first time one is added.
        if let url = try? URL.uttOverlayStyleFile,
           !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? style.write(to: url)
        }
        modifiedAt = Self.fileModifiedAt()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in Self.shared.reloadIfChanged() }
        }
    }

    private func reloadIfChanged() {
        let current = Self.fileModifiedAt()
        guard current != modifiedAt else { return }
        modifiedAt = current
        style = OverlayStyle.loaded()
    }

    private static func fileModifiedAt() -> Date? {
        guard let url = try? URL.uttOverlayStyleFile else { return nil }
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
