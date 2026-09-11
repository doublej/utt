import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// One extension's submenu, inside utt's own menu.
///
/// Not a status item of its own. The menu bar belongs to the person using the Mac,
/// and an extension is something they installed *into utt* — so it lives under utt's
/// mark, next to the transcript buttons, rather than planting a second icon beside
/// it. utt's own item stays one item however many extensions are installed.
///
/// Nothing here is declared twice: the submenu is built from what the extension
/// already says on its page, and every press writes the same `<id>.action.json`
/// the page writes.
struct ExtensionMenu: View {
    let store: StoreOf<AppFeature>
    let installed: InstalledExtension
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            // The extension's own words, from `<id>.status.json`. A `Text` in a menu
            // is a disabled line, which is what these are.
            ForEach(installed.status.keys.sorted(), id: \.self) { key in
                Text("\(key.asFieldLabel): \(installed.status[key] ?? "")")
            }

            if let daemon = installed.manifest.daemon {
                Divider()
                Text(daemonState.summary)
                Button("Restart") { store.send(.settings(.extensionDaemonRestartTapped(installed.id))) }
                // Served by utt itself, so it still works when the daemon behind
                // every other item in this menu is the thing that is broken.
                if let url = daemon.logURL {
                    Button("Reveal its log") { ExtensionDiagnostics.reveal(url) }
                }
            }

            if !installed.manifest.actions.isEmpty {
                Divider()
                ForEach(installed.manifest.actions) { action in
                    Button(action.label) { press(action) }
                }
            }

            Divider()
            Button("\(installed.manifest.name) settings…") { openSettings() }
        } label: {
            Label(installed.manifest.name, systemImage: symbol)
        }
    }

    /// An SF Symbol utt could not resolve would draw nothing at all, and a submenu
    /// with no mark beside it reads as a missing icon rather than as an extension.
    private var symbol: String {
        guard let named = installed.manifest.systemImage,
              NSImage(systemSymbolName: named, accessibilityDescription: nil) != nil
        else { return "puzzlepiece.extension" }
        return named
    }

    /// What launchd says, not what the extension says about itself.
    private var daemonState: ExtensionDaemonState {
        store.settings.daemonStates[installed.id] ?? .unknown
    }

    /// The page asks before a `confirms` action, and a menu is where a mis-click is
    /// likelier — so it asks on the same terms rather than firing.
    private func press(_ action: ExtensionAction) {
        if action.confirms {
            let alert = NSAlert()
            alert.messageText = action.label
            alert.informativeText = action.detail ?? ""
            alert.addButton(withTitle: action.label)
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        store.send(.settings(.extensionActionTapped(installed.id, key: action.key)))
    }

    /// `openWindow` first: the window may be closed rather than merely behind, and
    /// `SettingsRoute` can only front one that exists.
    private func openSettings() {
        openWindow(id: "main")
        SettingsRoute.shared.open(.extension(installed.manifest))
    }
}
