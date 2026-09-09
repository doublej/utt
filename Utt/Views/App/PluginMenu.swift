import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// One plugin's submenu, inside utt's own menu.
///
/// Not a status item of its own. The menu bar belongs to the person using the Mac,
/// and a plugin is something they installed *into utt* — so it lives under utt's
/// mark, next to the transcript buttons, rather than planting a second icon beside
/// it. utt's own item stays one item however many plugins are installed.
///
/// Nothing here is declared twice: the submenu is built from what the plugin
/// already says on its page, and every press writes the same `<id>.action.json`
/// the page writes.
struct PluginMenu: View {
    let store: StoreOf<AppFeature>
    let plugin: InstalledPlugin
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            // The plugin's own words, from `<id>.status.json`. A `Text` in a menu
            // is a disabled line, which is what these are.
            ForEach(plugin.status.keys.sorted(), id: \.self) { key in
                Text("\(key.asFieldLabel): \(plugin.status[key] ?? "")")
            }

            if plugin.manifest.daemon != nil {
                Divider()
                Text(daemonState.summary)
                Button("Restart") { store.send(.settings(.pluginDaemonRestartTapped(plugin.id))) }
            }

            if !plugin.manifest.actions.isEmpty {
                Divider()
                ForEach(plugin.manifest.actions) { action in
                    Button(action.label) { press(action) }
                }
            }

            Divider()
            Button("\(plugin.manifest.name) settings…") { openSettings() }
        } label: {
            Label(plugin.manifest.name, systemImage: symbol)
        }
    }

    /// An SF Symbol utt could not resolve would draw nothing at all, and a submenu
    /// with no mark beside it reads as a missing icon rather than as a plugin.
    private var symbol: String {
        guard let named = plugin.manifest.systemImage,
              NSImage(systemSymbolName: named, accessibilityDescription: nil) != nil
        else { return "puzzlepiece.extension" }
        return named
    }

    /// What launchd says, not what the plugin says about itself.
    private var daemonState: PluginDaemonState {
        store.settings.daemonStates[plugin.id] ?? .unknown
    }

    /// The page asks before a `confirms` action, and a menu is where a mis-click is
    /// likelier — so it asks on the same terms rather than firing.
    private func press(_ action: PluginAction) {
        if action.confirms {
            let alert = NSAlert()
            alert.messageText = action.label
            alert.informativeText = action.detail ?? ""
            alert.addButton(withTitle: action.label)
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        store.send(.settings(.pluginActionTapped(plugin.id, key: action.key)))
    }

    /// `openWindow` first: the window may be closed rather than merely behind, and
    /// `SettingsRoute` can only front one that exists.
    private func openSettings() {
        openWindow(id: "main")
        SettingsRoute.shared.open(.plugin(plugin.manifest))
    }
}
