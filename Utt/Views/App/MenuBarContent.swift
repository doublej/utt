import ComposableArchitecture
import SwiftUI

/// The status item itself: the same dot-matrix mark the window wears, cycling on
/// the same level, so the menu bar answers "is it hearing me?" without opening
/// anything.
///
/// `UttMark` cannot be used directly — a `MenuBarExtra` label draws through a path
/// where `Canvas` renders nothing at all, which collapses the status item to zero
/// width. An `Image` is one of the few things the label reliably accepts, so the
/// grid is drawn into an `NSImage` per pattern. That also costs the cross-fade;
/// stepping suits a dot matrix.
struct MenuBarIcon: View {
    let store: StoreOf<AppFeature>

    private static let size: CGFloat = 16

    private var driver: DotMatrixDriver { .shared }

    /// What the mark's speed is driven by. A plugin's clip has no meter to read —
    /// the audio was recorded somewhere else and arrives already finished — so it
    /// gets a steady rate that reads as working rather than as a level.
    private var level: Double {
        store.pluginActivity == nil ? Double(store.transcription.meterLevel) : 0.6
    }

    var body: some View {
        Image(nsImage: image(for: driver.pattern))
            .onChange(of: level) { _, newLevel in driver.level = newLevel }
            .onAppear { driver.level = level }
    }

    private func image(for pattern: Set<Int>) -> NSImage {
        let lit = NSColor(litColor)
        let unlit = NSColor.labelColor.withAlphaComponent(0.35)
        let side = Self.size
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            for index in 0..<36 {
                let isLit = pattern.contains(index)
                (isLit ? lit : unlit).setFill()
                NSBezierPath(ovalIn: DotMatrix.rect(for: index, size: side, lit: isLit)).fill()
            }
            return true
        }
    }

    /// The plugin's own colour while its clip is being transcribed, so a clip sent
    /// from a phone is visibly not something being said at this Mac. A plugin that
    /// declared no colour, or one utt could not read, falls back to utt's own.
    private var litColor: Color {
        if let rgb = store.pluginActivity?.rgb {
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
        if store.pluginActivity != nil { return Palette.accent }
        return store.transcription.isRecording ? Palette.recording : Palette.accent
    }
}

/// Menu bar item. The status line is the point: a global-hotkey app with no
/// visible window still has to answer "is it listening?".
struct MenuBarContent: View {
    let store: StoreOf<AppFeature>
    @Environment(\.openWindow) private var openWindow
    @Shared(.uttHistory) private var transcripts

    var body: some View {
        Text(statusLine)

        Divider()

        Button("Paste last transcript") { store.send(.pasteLastTapped) }
            .disabled(transcripts.history.isEmpty)
        Button("Copy last transcript") { store.send(.copyLastTapped) }
            .disabled(transcripts.history.isEmpty)

        if !menuPlugins.isEmpty {
            Divider()
            ForEach(menuPlugins) { plugin in
                PluginMenu(store: store, plugin: plugin)
            }
        }

        Divider()

        Button("Open utt") {
            openWindow(id: "main")
            // `openWindow` alone shows the window without making utt active — a
            // MenuBarExtra click does not activate the app that owns it.
            AppActivation.front()
            DispatchQueue.main.async {
                NSApp.uttMainWindow?.makeKeyAndOrderFront(nil)
            }
        }
        if store.updatesConfigured {
            Button("Check for Updates…") { store.send(.checkForUpdatesTapped) }
        }
        Button("Quit utt") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// A plugin appears here only if it asked to. One that did gets a submenu
    /// rather than an item of its own — see `PluginMenu`.
    private var menuPlugins: [InstalledPlugin] {
        store.settings.plugins.filter(\.manifest.showsInMenuBar)
    }

    private var statusLine: String {
        if store.needsRelaunch { return "Restart to apply permissions" }
        if !store.missingPermissions.isEmpty {
            // The menu bar has no room to explain and no button to fix it with.
            // The window has both, so it names the permissions and this points there.
            return "Not ready — open utt to finish setup"
        }
        switch store.transcription.status {
        case .idle:
            switch store.model {
            case let .downloading(fraction): return "Downloading model \(Int(fraction * 100))%"
            case .idle, .loading: return "Loading model…"
            case .ready: return "Ready"
            case let .failed(message): return message
            }
        case .recording: return "Recording"
        case .transcribing: return "Transcribing…"
        case let .failed(message): return message
        }
    }
}
