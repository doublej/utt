import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// A menu bar item of a plugin's own.
///
/// utt's own mark stays what it is — one icon, utt's status. A plugin that asked
/// for `showsInMenuBar` gets a second item beside it, carrying its own symbol and
/// colour, and a menu built from what that plugin already declares: its status
/// lines, its buttons, its daemon. Nothing new to declare but the flag.
///
/// AppKit rather than `MenuBarExtra`, because the number of items is data: a scene
/// is declared once at compile time and there is no `ForEach` for it.
@MainActor
final class PluginMenuBar {
    static let shared = PluginMenuBar()

    private var items: [String: NSStatusItem] = [:]
    private var delegates: [String: MenuSource] = [:]

    private init() {}

    /// Brings the items in line with the plugins that want one. Cheap to call on
    /// every poll — it does nothing unless the set has changed.
    func sync(_ plugins: [InstalledPlugin], store: StoreOf<AppFeature>) {
        let wanted = plugins.filter(\.manifest.showsInMenuBar)
        let ids = Set(wanted.map(\.id))

        for (id, item) in items where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            items[id] = nil
            delegates[id] = nil
        }

        for plugin in wanted {
            let item = items[plugin.id] ?? make(for: plugin.id, store: store)
            apply(plugin, to: item)
            delegates[plugin.id]?.plugin = plugin
        }
    }

    private func make(for id: String, store: StoreOf<AppFeature>) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        // Built when it is opened, not when it is made: a status line the plugin
        // rewrote a second ago should be the one on screen.
        let source = MenuSource(store: store)
        menu.delegate = source
        item.menu = menu
        items[id] = item
        delegates[id] = source
        return item
    }

    private func apply(_ plugin: InstalledPlugin, to item: NSStatusItem) {
        guard let button = item.button else { return }
        let symbol = plugin.manifest.systemImage ?? "puzzlepiece.extension"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: plugin.manifest.name)
            ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: plugin.manifest.name)
        // A tinted icon is drawn as-is; without a colour it is a template, which is
        // what lets the menu bar invert it for a light or dark background.
        image?.isTemplate = plugin.manifest.rgb == nil
        button.image = image
        if let rgb = plugin.manifest.rgb {
            button.contentTintColor = NSColor(
                red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        } else {
            button.contentTintColor = nil
        }
        // What the plugin says about itself, in the place a hover already looks.
        let status = plugin.status.keys.sorted().first.map { "\($0): \(plugin.status[$0] ?? "")" }
        button.toolTip = [plugin.manifest.name, status].compactMap { $0 }.joined(separator: " — ")
    }
}

/// Rebuilds one plugin's menu each time it is opened.
@MainActor
private final class MenuSource: NSObject, NSMenuDelegate {
    var plugin: InstalledPlugin?
    private let store: StoreOf<AppFeature>

    init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let plugin else { return }

        for key in plugin.status.keys.sorted() {
            let line = NSMenuItem(
                title: "\(key.asFieldLabel): \(plugin.status[key] ?? "")",
                action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }

        if plugin.manifest.daemon != nil {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let state = store.settings.daemonStates[plugin.id] ?? .unknown
            let line = NSMenuItem(title: state.summary, action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
            menu.addItem(action(title: "Restart", tag: .restart))
        }

        if !plugin.manifest.actions.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for declared in plugin.manifest.actions {
                let item = action(title: declared.label, tag: .plugin)
                item.representedObject = declared.key
                menu.addItem(item)
            }
        }

        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(action(title: "\(plugin.manifest.name) settings…", tag: .settings))
    }

    private enum Tag: Int {
        case restart, plugin, settings
    }

    /// The page asks before a `confirms` action, and a menu bar item is where a
    /// mis-click is likelier — so it asks on the same terms rather than firing.
    private func confirmed(_ declared: PluginAction) -> Bool {
        let alert = NSAlert()
        alert.messageText = declared.label
        alert.informativeText = declared.detail ?? ""
        alert.addButton(withTitle: declared.label)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func action(title: String, tag: Tag) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(menuItemChosen(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag.rawValue
        return item
    }

    @objc private func menuItemChosen(_ sender: NSMenuItem) {
        guard let plugin, let tag = Tag(rawValue: sender.tag) else { return }
        switch tag {
        case .restart:
            store.send(.settings(.pluginDaemonRestartTapped(plugin.id)))
        case .plugin:
            guard let key = sender.representedObject as? String,
                  let declared = plugin.manifest.actions.first(where: { $0.key == key }),
                  !declared.confirms || confirmed(declared)
            else { return }
            store.send(.settings(.pluginActionTapped(plugin.id, key: key)))
        case .settings:
            SettingsRoute.shared.open(.plugin(plugin.manifest))
        }
    }
}
