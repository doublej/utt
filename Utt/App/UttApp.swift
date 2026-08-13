import ComposableArchitecture
import SwiftUI
import UttCore

@main
struct UttApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        Window("utt", id: "main") {
            AppRootView(store: Self.store)
        }
        // The window has three fixed shapes and must follow the content into each
        // one. `setContentSize` from the AppKit side loses: SwiftUI re-imposes its
        // own frame right after. Clamping the window to the content is the only
        // sizing that sticks — and the pill it used to strand in an 80pt window is
        // fine now that WindowConfigurator drops `.titled` there.
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarContent(store: Self.store)
        } label: {
            MenuBarIcon(store: Self.store)
        }
    }
}
