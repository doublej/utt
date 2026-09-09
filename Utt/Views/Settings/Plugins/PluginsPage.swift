import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// What a plugin is, what is installed, and how to write one.
///
/// Sits above the installed plugins in the rail for the same reason the API page
/// sits above nothing: a person who has never installed one arrives here first,
/// and an empty Connect group with no explanation reads as a broken feature.
struct PluginsPage: View {
    let store: StoreOf<AppFeature>
    @State private var copied = false

    private var installed: [InstalledPlugin] { store.settings.plugins }

    var body: some View {
        Card {
            Text("A plugin is another program on this Mac that wants a settings page in this window. It declares what it is in a file; utt draws the page and writes your choices back where the plugin can read them. Nothing is downloaded and nothing runs inside utt — a plugin is a program you installed yourself.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        SettingsGroup("Available") {
            ForEach(Self.known) { entry in
                SettingRow(entry.name, detail: entry.blurb) {
                    if let plugin = installed.first(where: { $0.id == entry.id }) {
                        Button("Open") { SettingsRoute.shared.section = .plugin(plugin.manifest) }
                            .font(Typography.metadata)
                    } else {
                        Link("Get", destination: entry.url)
                            .font(Typography.metadata)
                    }
                }
            }
        }

        SettingsGroup("Installed") {
            if installed.isEmpty {
                SettingRow("Nothing yet", detail: "An installed plugin appears here and in the rail on the left.") {
                    EmptyView()
                }
            } else {
                ForEach(installed) { plugin in
                    SettingRow(plugin.manifest.name, detail: plugin.manifest.blurb) {
                        Button("Open") { SettingsRoute.shared.section = .plugin(plugin.manifest) }
                            .font(Typography.metadata)
                    }
                }
            }
        }

        SettingsGroup("Write one") {
            SettingRow(
                "Guide for an LLM",
                detail: "The whole format — the manifest, the values file utt writes back, and the rules that decide whether a plugin is accepted. Paste it into a model along with your project."
            ) {
                Button(copied ? "Copied" : "Copy guide") { copyGuide() }
                    .font(Typography.metadata)
            }
            SettingRow("Plugins folder", detail: directory) {
                Button("Open") { openDirectory() }
                    .font(Typography.metadata)
            }
        }
    }

    /// One entry in the short list of plugins worth knowing about.
    private struct Known: Identifiable {
        let id: String
        let name: String
        let blurb: String
        let url: URL
    }

    /// Hand-kept, and deliberately not fetched from anywhere: utt has no plugin
    /// registry, and a list that phoned home would be a network call this app does
    /// not otherwise make.
    private static let known = [
        Known(
            id: "deckhand",
            name: "Deckhand",
            blurb: "Relays what you dictate into a terminal session, from your phone or this Mac.",
            url: URL(string: "https://github.com/jurrejan/deckhand")!
        )
    ]

    /// Shown rather than hidden: it is where a plugin author puts their manifest,
    /// and where a suspicious person goes to see what has declared itself.
    private var directory: String {
        (try? URL.uttPluginsDirectory.path(percentEncoded: false)) ?? "Application Support"
    }

    private func openDirectory() {
        guard let url = try? URL.uttPluginsDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyGuide() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PluginGuide.markdown(directory: directory), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
