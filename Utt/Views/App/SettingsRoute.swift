import AppKit
import Observation
import SwiftUI

/// Which settings section is showing, and whether settings are showing at all.
///
/// Lifted out of `AppRootView`'s `@State` for one reason: the transcript panel is a
/// separate `NSPanel` with its own hosting view, so "Add rule" over there has no
/// binding to reach into this window's state with. Same shape as
/// `OverlayStyleStore` — a `@MainActor @Observable` singleton the views read.
@MainActor
@Observable
final class SettingsRoute {
    static let shared = SettingsRoute()

    var isOpen = false
    var tab: SettingsPanel.Tab = .recording

    private init() {}

    /// Bring the window forward on `tab`. Activation is deliberate here and only
    /// here: the user clicked a button asking to be taken somewhere. The panel
    /// itself must never do this — see `TranscriptHUD`.
    func open(_ tab: SettingsPanel.Tab) {
        self.tab = tab
        isOpen = true
        NSApp.activate()
        // Deferred a turn: if the window is currently the pill it is borderless
        // right now — AppRootView expands on `isOpen` and WindowConfigurator
        // restores `.titled` on the next render pass, and only then can the
        // window become key.
        DispatchQueue.main.async {
            NSApp.uttMainWindow?.makeKeyAndOrderFront(nil)
        }
    }
}
