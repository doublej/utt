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
            Text("A plugin is a separate program you install yourself, like Deckhand, that works with utt. Instead of a settings window of its own it gets a page in this one: you change its settings here, utt saves them to a file the program reads, and hands it what it asked for — the API token, and your transcripts as they finish. Each plugin's page lists what it receives. Nothing is downloaded, and nothing runs inside utt.")
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
                SettingRow("Nothing yet", detail: "Install one and it shows up here, and as its own row in the rail under Plugins.") {
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
                detail: "Everything a plugin has to write: the manifest, the values file utt writes back, and what gets a manifest refused. Paste it into an LLM together with your project."
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
            blurb: "Dictate into a Claude Code session from your phone. The clip comes to this Mac, utt turns it into text, and the words land in the session.",
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
