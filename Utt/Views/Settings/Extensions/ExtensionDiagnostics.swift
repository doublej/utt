import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// utt's own account of what it did with an extension, on the page rather than in
/// the unified log.
///
/// Every line here used to go to `os_log` and nowhere else, which meant the person
/// with a broken extension had to be told to run `log stream` — and `log show`,
/// the obvious thing to reach for, cannot open the store from an ordinary shell and
/// answers with nothing rather than an error. So the same lines are kept in memory
/// and shown where the extension is.
struct ExtensionLogGroup: View {
    let title: String
    let entries: [ExtensionLogEntry]
    /// The extensions list shows the whole log, so a row there has to say which
    /// extension it is about. A page already knows.
    var namesExtensions = false
    /// A page is not a log viewer. Enough to see what just happened and what keeps
    /// happening; the rest is what the report is for.
    var limit = 10
    let empty: String

    var body: some View {
        SettingsGroup(title) {
            if entries.isEmpty {
                SettingRow("Nothing yet", detail: empty) { EmptyView() }
            } else {
                ForEach(entries.prefix(limit)) { entry in
                    SettingRow(entry.message, detail: detail(entry), detailTint: tint(entry)) {
                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                            .font(Typography.metadata)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                if entries.count > limit {
                    SettingRow(
                        "\(entries.count - limit) older",
                        detail: "Copy the diagnostics on the Extensions page to see all of it."
                    ) { EmptyView() }
                }
            }
        }
    }

    private func detail(_ entry: ExtensionLogEntry) -> String? {
        let parts = [
            namesExtensions ? entry.extensionID : nil,
            // A standing problem is one line said over and over. The number is what
            // separates "it happened once" from "it is happening now".
            entry.count > 1 ? "\(entry.count) times" : nil
        ]
        let detail = parts.compactMap { $0 }.joined(separator: " · ")
        return detail.isEmpty ? nil : detail
    }

    private func tint(_ entry: ExtensionLogEntry) -> Color {
        entry.level == .problem ? Palette.warning : Palette.textTertiary
    }
}

/// The whole state of extensions on this Mac as text, and the one safe thing utt
/// does with a path an extension named.
enum ExtensionDiagnostics {
    /// Reveals in the Finder rather than opening. `NSWorkspace.open` is
    /// LaunchServices picking an app by extension, so a manifest naming a
    /// `.command` would turn "drop a file in a folder" into "run this as the user".
    /// Finder's worst case is that it shows you a file.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// What to paste into an issue. Everything the pages show, plus the parts of the
    /// log that have scrolled off them — an extension author cannot read the person's
    /// screen, and "it does not work" is what they get instead.
    static func report(
        extensions: [InstalledExtension],
        daemons: [String: ExtensionDaemonState],
        log: [ExtensionLogEntry],
        directory: String
    ) -> String {
        var lines = [
            "utt \(version) · \(extensions.count) extension\(extensions.count == 1 ? "" : "s")",
            "folder: \(directory)"
        ]
        for installed in extensions {
            lines.append("")
            lines += describe(installed, daemon: daemons[installed.id])
        }
        lines.append("")
        lines.append("log (\(log.count))")
        lines += log.map { entry in
            let stamp = entry.timestamp.formatted(date: .omitted, time: .standard)
            let repeats = entry.count > 1 ? " ×\(entry.count)" : ""
            return "  \(stamp)  \(entry.level.rawValue)  \(entry.extensionID ?? "—")  \(entry.message)\(repeats)"
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(
        _ installed: InstalledExtension, daemon state: ExtensionDaemonState?
    ) -> [String] {
        let manifest = installed.manifest
        var lines = ["\(installed.id) — \(manifest.name)"]
        lines.append("  \(installed.consent.rawValue) · queue \(installed.priority.rawValue)")
        if !asked(manifest).isEmpty { lines.append("  asks for: \(asked(manifest).joined(separator: ", "))") }
        if !manifest.skipsTextStages.isEmpty {
            lines.append("  skips: \(manifest.skipsTextStages.map(\.rawValue).sorted().joined(separator: ", "))")
        }
        for setting in installed.settings.sorted(by: { $0.key < $1.key }) {
            lines.append("  setting \(setting.key) = \(summary(of: setting))")
        }
        // The extension's own words, verbatim: the one part of this report utt did
        // not write and cannot vouch for.
        for key in installed.status.keys.sorted() {
            lines.append("  status \(key) = \(installed.status[key] ?? "")")
        }
        if let daemon = manifest.daemon {
            lines.append("  daemon \(daemon.label): \(state?.summary ?? "not read")")
            if let url = daemon.logURL { lines.append("  daemon log: \(url.path(percentEncoded: false))") }
        }
        return lines
    }

    /// A setting's value, except free text — which is the one thing on the page the
    /// person typed themselves, and may well be a key they pasted into an
    /// extension's field. This report exists to be pasted somewhere else.
    private static func summary(of setting: ExtensionSetting) -> String {
        switch setting.value {
        case let .bool(flag): "\(flag)"
        case let .number(number): "\(number)"
        case let .string(text) where setting.kind == .choice: text
        case let .string(text): text.isEmpty ? "empty" : "\(text.count) characters"
        }
    }

    private static func asked(_ manifest: ExtensionManifest) -> [String] {
        [
            manifest.sendsAudio ? "audio" : nil,
            manifest.wantsTranscripts ? "transcripts" : nil,
            manifest.wantsPartials ? "partials" : nil,
            manifest.filtersTranscripts ? "rewrites" : nil,
            manifest.needsApi ? "API token" : nil,
            manifest.showsInMenuBar ? "menu bar" : nil
        ].compactMap { $0 }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
