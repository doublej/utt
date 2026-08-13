import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate {
    @Dependency(\.recording) private var recording
    @Shared(.uttSettings) private var settings

    /// Held for the app's lifetime — the panel goes away with it.
    private var overlay: RecordingOverlay?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist declares LSUIElement so the app can start quiet as a login
        // item; the Dock icon is a runtime decision, not a bundle one.
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        clearOrphanedRecordings()
        // Before the quiet-launch sweep, which only closes windows that can become
        // main — a borderless panel cannot, so the overlay survives it.
        overlay = RecordingOverlay(store: UttApp.store)
        closeWindowIfLaunchedQuietly(notification)

        // Bootstrap belongs to the app, not to a view: with LSUIElement the window
        // may never appear, and a `.task` on it would leave the hotkey dead.
        Task { await UttApp.store.send(.task).finish() }
    }

    /// utty's mirror-image bug was orphaned processes on ⌘Q. Here the risk is a
    /// half-written wav and an engine still holding the mic, so termination waits —
    /// briefly — for cleanup instead of firing and forgetting.
    func applicationWillTerminate(_ notification: Notification) {
        let done = Flag()
        Task {
            await recording.cancel()
            done.value = true
        }
        let deadline = Date().addingTimeInterval(3)
        while !done.value, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if !done.value { log.error("recording cleanup did not finish within 3s") }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Started by launchd as a login item rather than by the user, so nothing
    /// should appear on screen — the menu bar item is the whole announcement.
    ///
    /// `launchIsDefaultUserInfoKey` is the documented signal and the only reliable
    /// one: the parent process is launchd either way, so `getppid` cannot tell the
    /// two apart. The window is closed rather than never opened because SwiftUI
    /// creates it as part of building the scene; closing it is reversible from the
    /// menu bar, and if the filter ever misses, the app simply behaves as it does
    /// today.
    @MainActor
    private func closeWindowIfLaunchedQuietly(_ notification: Notification) {
        let byUser = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool
        guard byUser == false else { return }
        DispatchQueue.main.async {
            // MenuBarExtra's window cannot become main; the panel can.
            NSApp.windows.filter(\.canBecomeMain).forEach { $0.close() }
            log.notice("launched as a login item — staying in the menu bar")
        }
    }

    /// A wav in the recordings directory at launch was orphaned by a crash.
    private func clearOrphanedRecordings() {
        guard let directory = try? URL.uttRecordings,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "wav" {
            try? FileManager.default.removeItem(at: file)
        }
        if !files.isEmpty { log.notice("cleared \(files.count) orphaned recording(s)") }
    }
}

private final class Flag: @unchecked Sendable {
    var value = false
}
