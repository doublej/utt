import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate {
    @Dependency(\.recording) private var recording
    @Shared(.uttSettings) private var settings

    /// Held for the app's lifetime — the panels go away with it.
    private var overlay: RecordingOverlay?
    private var hud: TranscriptHUD?

    /// False until the launch has settled — see `presentWindowUnlessLaunchedQuietly`.
    private var presentsWindowOnActivation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UttTests loads the app as its host. Booting the real store there resolves
        // every dependency to its unimplemented test value — the first one reached,
        // the permission poll's clock, aborts the whole process.
        guard NSClassFromString("XCTestCase") == nil else { return }
        // A runtime decision, not a bundle one. Info.plist deliberately omits
        // LSUIElement — see the note there — so utt starts as a regular app and
        // drops to accessory here when the user has hidden the Dock icon.
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        clearOrphanedRecordings()
        // Before the quiet-launch sweep, which only closes windows that can become
        // main — a borderless panel cannot, so the overlay survives it.
        overlay = RecordingOverlay(store: UttApp.store)
        hud = TranscriptHUD(store: UttApp.store)
        presentWindowUnlessLaunchedQuietly(notification)

        // Bootstrap belongs to the app, not to a view: on a login-item launch the
        // window is closed again below, and a `.task` on it would leave the hotkey
        // dead.
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

    /// Bringing utt to the front with its window closed used to change the menu bar
    /// and nothing else — the scene's window stays closed until something reopens
    /// it, and only the Window menu item SwiftUI generates did. A Dock click and
    /// `open -a utt` arrive here as a reopen; ⌘-Tab sends no event at all and
    /// arrives as an activation instead. utt has one window, so both answer the same.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        presentMainWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard presentsWindowOnActivation else { return }
        presentMainWindow()
    }

    /// Silent while the window is already on screen. The pill is that same window,
    /// and clicking it activates utt — without this guard, every click on the pill
    /// would drag it out of its floating level and make it key.
    @MainActor
    private func presentMainWindow() {
        guard let window = NSApp.uttMainWindow, !window.isVisible else { return }
        window.makeKeyAndOrderFront(nil)
    }

    /// `utt://start`, `utt://stop`, `utt://toggle`, `utt://cancel` — the hotkey's
    /// four decisions, for anything that can open a URL: Raycast, Shortcuts, a
    /// Stream Deck, `open` in a script.
    ///
    /// Callers must use `open -g`. utt does not activate itself here, but a plain
    /// `open` does it for them, and the frontmost app at the moment a recording
    /// stops is the app the transcript is pasted into — so a foregrounding caller
    /// dictates into utt's own window.
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let action = Self.action(for: url) else {
                log.notice("ignoring unknown url \(url.absoluteString, privacy: .public)")
                continue
            }
            UttApp.store.send(.transcription(action))
        }
    }

    @MainActor
    private static func action(for url: URL) -> TranscriptionFeature.Action? {
        guard url.scheme == "utt" else { return nil }
        switch url.host() {
        case "start": return .startRecording
        case "stop": return .stopRecording
        // Not silent: the user asked for this, so the discard chime is feedback,
        // not an apology for a keypress they did not mean.
        case "cancel": return .cancelRecording(silent: false)
        case "toggle": return UttApp.store.transcription.isRecording ? .stopRecording : .startRecording
        default: return nil
        }
    }

    /// Two launches, two behaviours. Started by launchd as a login item, nothing
    /// should appear on screen — the menu bar item is the whole announcement.
    /// Started by a person, utt comes to the front like any other app.
    ///
    /// `launchIsDefaultUserInfoKey` is the documented signal and the only reliable
    /// one: the parent process is launchd either way, so `getppid` cannot tell the
    /// two apart. The window is closed rather than never opened because SwiftUI
    /// creates it as part of building the scene; closing it is reversible from the
    /// menu bar, and if the filter ever misses, the app simply behaves as it does
    /// today.
    ///
    /// The bundle used to declare `LSUIElement` to keep the login-item launch quiet.
    /// That started *every* launch as an accessory, and an accessory app is not
    /// granted activation by its own launch — so double-clicking utt opened its
    /// window behind whatever was already on screen, and no `NSApp.activate()` here
    /// could take the focus back. The key is gone; this method covers both launches.
    @MainActor
    private func presentWindowUnlessLaunchedQuietly(_ notification: Notification) {
        let byUser = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool
        // Deferred a turn of the run loop either way: SwiftUI builds the scene's
        // window as part of finishing launch, so there is nothing to close or raise
        // yet at the point this is called.
        DispatchQueue.main.async {
            // Matched by identifier, not `canBecomeMain`: in pill mode the window
            // is borderless and fails that test, which made this a silent no-op.
            guard byUser != false else {
                NSApp.uttMainWindow?.close()
                log.notice("launched as a login item — staying in the menu bar")
                // At login utt can be the only app running and end up active on its
                // own, which would send the close above straight back through
                // `applicationDidBecomeActive`. Nobody ⌘-Tabs to an app two seconds
                // into logging in.
                // ponytail: a delay, not a signal — AppKit has no "login settled" event.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.presentsWindowOnActivation = true
                }
                return
            }
            NSApp.activate()
            NSApp.uttMainWindow?.makeKeyAndOrderFront(nil)
            self.presentsWindowOnActivation = true
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
