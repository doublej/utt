import AppKit
import Observation
import SwiftUI

/// Which section the rail is on, and a way to get there from outside the window.
///
/// Lifted out of `AppRootView`'s `@State` for one reason: the transcript panel is a
/// separate `NSPanel` with its own hosting view, so "Add rule" over there has no
/// binding to reach into this window's state with. Same shape as
/// `OverlayStyleStore` — a `@MainActor @Observable` singleton the views read.
@MainActor
@Observable
final class SettingsRoute {
    static let shared = SettingsRoute()

    var section: AppSection = .history

    /// Settings or transcripts. Kept as a switch because the pill toggles it.
    var isOpen: Bool {
        get { section.isSettings }
        set { section = newValue ? .hotkey : .history }
    }

    private init() {}

    /// Bring the window forward on `section`. Activation is deliberate here and only
    /// here: the user clicked a button asking to be taken somewhere. The panel
    /// itself must never do this — see `TranscriptHUD`.
    func open(_ section: AppSection) {
        self.section = section
        AppActivation.front()
        // Deferred a turn: if the window is currently the pill it is borderless
        // right now — AppRootView expands on `isOpen` and WindowConfigurator
        // restores `.titled` on the next render pass, and only then can the
        // window become key.
        DispatchQueue.main.async {
            NSApp.uttMainWindow?.makeKeyAndOrderFront(nil)
        }
    }
}
