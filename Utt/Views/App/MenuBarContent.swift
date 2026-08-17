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
    private var level: Double { Double(store.transcription.meterLevel) }

    var body: some View {
        Image(nsImage: image(for: driver.pattern))
            .onChange(of: level) { _, newLevel in driver.level = newLevel }
            .onAppear { driver.level = level }
    }

    private func image(for pattern: Set<Int>) -> NSImage {
        let lit = NSColor(store.transcription.isRecording ? Palette.recording : Palette.accent)
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

        Divider()

        Button("Open utt") { openWindow(id: "main") }
        if store.updatesConfigured {
            Button("Check for Updates…") { store.send(.checkForUpdatesTapped) }
        }
        Button("Quit utt") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        if store.needsRelaunch { return "Restart to apply permissions" }
        if !store.missingPermissions.isEmpty {
            return "Needs \(store.missingPermissions.map(\.title).joined(separator: ", "))"
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
