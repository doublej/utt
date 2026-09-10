import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// What an extension is, what is installed, and how to write one.
///
/// Sits above the installed extensions in the rail for the same reason the API page
/// sits above nothing: a person who has never installed one arrives here first,
/// and an empty Connect group with no explanation reads as a broken feature.
struct ExtensionsPage: View {
    let store: StoreOf<AppFeature>
    @State private var copied = false

    private var installed: [InstalledExtension] { store.settings.extensions }

    /// The hand-kept list, minus anything already installed — those have a real
    /// page of their own and belong under Installed.
    private var available: [Known] {
        Self.known.filter { entry in !installed.contains { $0.id == entry.id } }
    }

    var body: some View {
        Card {
            Text("An extension is a separate program you install yourself, like Deckhand, that works with utt. It gets a page in this window instead of a settings window of its own. What you change here is saved to a file the program reads. An extension can also ask for more: audio to transcribe, your transcripts as they finish, a chance to rewrite each one before it is pasted, or the API token. Its page lists exactly what it gets. Nothing is downloaded, and nothing runs inside utt.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Only the ones you could still add. An extension that is installed belongs
        // under Installed and nowhere else — listing it twice made utt look like it
        // had two Deckhands.
        if !available.isEmpty {
            SettingsGroup("Known extensions") {
                ForEach(available) { entry in
                    SettingRow(entry.name, detail: entry.blurb) {
                        Link("Get", destination: entry.url)
                            .font(Typography.metadata)
                    }
                }
            }
        }

        SettingsGroup("Installed") {
            if installed.isEmpty {
                SettingRow("Nothing yet", detail: "Install one and it shows up here, and as its own row in the rail under Extensions.") {
                    EmptyView()
                }
            } else {
                ForEach(installed) { installed in
                    SettingRow(installed.manifest.name, detail: installed.manifest.blurb) {
                        Button("Open") { SettingsRoute.shared.section = .extension(installed.manifest) }
                            .font(Typography.metadata)
                    }
                }
            }
        }

        SettingsGroup("Write one") {
            SettingRow(
                "Guide for an LLM",
                detail: "The whole contract: the manifest, the files utt writes back, the audio lane, and what gets a manifest refused. Paste it into an LLM together with your project and ask for an extension."
            ) {
                Button(copied ? "Copied" : "Copy guide") { copyGuide() }
                    .font(Typography.metadata)
            }
            SettingRow("Extensions folder", detail: directory) {
                Button("Open") { openDirectory() }
                    .font(Typography.metadata)
            }
        }
    }

    /// One entry in the short list of extensions worth knowing about.
    private struct Known: Identifiable {
        let id: String
        let name: String
        let blurb: String
        let url: URL
    }

    /// Hand-kept, and deliberately not fetched from anywhere: utt has no extension
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

    /// Shown rather than hidden: it is where an extension author puts their manifest,
    /// and where a suspicious person goes to see what has declared itself.
    private var directory: String {
        (try? URL.uttExtensionsDirectory.path(percentEncoded: false)) ?? "Application Support"
    }

    private func openDirectory() {
        guard let url = try? URL.uttExtensionsDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyGuide() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ExtensionGuide.markdown(directory: directory), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
