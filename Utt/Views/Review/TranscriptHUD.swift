import AppKit
import ComposableArchitecture
import SwiftUI

/// The delivery panel: what utt heard, where it went, and — in review mode — a
/// chance to stop it before it goes anywhere.
///
/// Same panel setup as `RecordingOverlay`, and for the same reason: this appears
/// while the user is working in somebody else's app, so it cannot live inside utt's
/// window. **Non-activating and never key.** utt pastes into whatever app is
/// frontmost; a panel that takes focus would paste into itself.
///
/// One difference from the recording overlay: this one has buttons, so it cannot be
/// mouse-transparent. It is click-through only while it is drawing nothing —
/// otherwise an invisible rectangle would eat clicks at the bottom of every screen.
@MainActor
final class TranscriptHUD {
    private let panel: NSPanel

    private static let size = CGSize(width: 460, height: 200)
    /// Clear of the Dock: `visibleFrame`, not `frame`.
    private static let bottomInset: CGFloat = 16

    init(store: StoreOf<AppFeature>) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle
        ]

        // Ordered front for the whole run, drawing nothing when there is nothing to
        // say — panel visibility stays a SwiftUI decision, exactly as the recording
        // overlay does it. The callback is where the two AppKit-only facts live:
        // which screen it belongs on, and whether it is currently in the way.
        panel.contentView = NSHostingView(
            rootView: TranscriptHUDView(store: store) { [weak panel] showing in
                guard let panel else { return }
                panel.ignoresMouseEvents = !showing
                if showing { Self.placeOnActiveScreen(panel) }
            }
        )
        Self.placeOnActiveScreen(panel)
        panel.orderFrontRegardless()
    }

    /// Bottom-centre of the display the mouse is on, re-evaluated every time the
    /// panel appears — that display is the one being worked on, and it changes.
    private static func placeOnActiveScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(
            NSPoint(x: frame.midX - size.width / 2, y: frame.minY + bottomInset)
        )
    }
}
