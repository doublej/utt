import ComposableArchitecture
import SwiftUI
import UttCore

/// A page utt did not write. The controls come from the extension's manifest, so
/// this view renders a schema rather than a fixed list of settings — the one
/// place in the app where that is true.
///
/// Everything shown here was written by another process. It is displayed, never
/// interpreted: the status block is the extension's own words, and the settings are
/// whatever survived `ExtensionManifest.sanitized()`.
struct ExtensionPage: View {
    let store: StoreOf<AppFeature>
    let installed: InstalledExtension
    @Shared(.uttSettings) private var settings
    @State private var confirming: ExtensionAction?
    @State private var removing = false

    var body: some View {
        if !installed.status.isEmpty {
            SettingsGroup("Status") {
                // Alphabetical: a JSON object has no order to preserve, and
                // inventing one would put the fields in an order the extension
                // did not choose either.
                ForEach(installed.status.keys.sorted(), id: \.self) { key in
                    SettingRow(key.asFieldLabel) {
                        Text(installed.status[key] ?? "")
                            .font(Typography.metadata)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }

        if let daemon = installed.manifest.daemon {
            SettingsGroup("Daemon") {
                SettingRow(
                    daemon.label,
                    detail: daemonDetail,
                    detailTint: daemonState == .stopped ? Palette.warning : Palette.textTertiary
                ) {
                    Button("Restart") {
                        store.send(.settings(.extensionDaemonRestartTapped(installed.id)))
                    }
                    .font(Typography.metadata)
                }
            }
        }

        if !installed.manifest.actions.isEmpty {
            SettingsGroup("Actions") {
                ForEach(installed.manifest.actions) { action in
                    SettingRow(action.label, detail: action.detail) {
                        Button(action.label) { press(action) }
                            .font(Typography.metadata)
                    }
                }
            }
        }

        if installed.settings.isEmpty {
            Card {
                Text("\(installed.manifest.name) has no settings to change here.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
        } else {
            SettingsGroup("Settings") {
                ForEach(installed.settings) { setting in
                    row(setting)
                }
            }
        }

        confirmation

        if installed.manifest.wantsTranscripts || installed.manifest.needsApi || installed.manifest.sendsAudio
            || installed.manifest.filtersTranscripts {
            SettingsGroup("Access") {
                if installed.manifest.filtersTranscripts {
                    SettingRow(
                        "Rewrites your transcripts",
                        detail: "Sees each transcript before it is pasted and can hand back different text. If it does not answer within two seconds, the text goes through as you said it.",
                        detailTint: Palette.textTertiary
                    ) {
                        Image(systemName: "wand.and.sparkles").foregroundStyle(Palette.textTertiary)
                    }
                }
                if installed.manifest.sendsAudio {
                    SettingRow(
                        "Sends audio to be transcribed",
                        detail: "Drops clips in a folder of its own and gets the text back. Transcribed on this Mac, with your engine and your text rules. Nothing goes over the network."
                    ) {
                        Image(systemName: "waveform").foregroundStyle(Palette.textTertiary)
                    }
                }
                if !installed.manifest.skipsTextStages.isEmpty {
                    SettingRow("Skips some of your text rules", detail: skipNote) {
                        Image(systemName: "text.badge.minus").foregroundStyle(Palette.textTertiary)
                    }
                }
                if installed.manifest.wantsTranscripts {
                    SettingRow(
                        "Receives your transcripts",
                        detail: "Everything you dictate on this Mac is written to this extension's own file as it finishes, whether or not utt keeps it in History.",
                        detailTint: Palette.textTertiary
                    ) {
                        Image(systemName: "text.quote").foregroundStyle(Palette.textTertiary)
                    }
                }
                if installed.manifest.needsApi {
                    SettingRow(
                        "Holds the API token",
                        detail: apiNote,
                        detailTint: settings.api.enabled ? Palette.textTertiary : Palette.warning
                    ) {
                        Image(systemName: "network").foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }

        management
        removalConfirmation
    }

    /// utt's own switch and its own eject button, last on the page: everything
    /// above is the extension describing itself; this is what the person can do to it.
    private var management: some View {
        SettingsGroup("In utt") {
            SettingRow(
                "Enabled",
                detail: "Off keeps this page and the extension's settings, but utt stops handing it transcripts and audio, stops waiting for its answers, and takes it out of the menu bar."
            ) {
                Toggle("Enabled", isOn: Binding(
                    get: { installed.enabled },
                    set: { store.send(.settings(.extensionEnabledChanged(installed.id, $0))) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Palette.accent)
            }
            SettingRow(
                "Remove from utt",
                detail: "Moves the files utt keeps for \(installed.manifest.name) to the Trash: this page, its settings and its status. The program itself is not touched, and one that is still running may add itself back."
            ) {
                Button("Remove…") { removing = true }
                    .font(Typography.metadata)
            }
        }
    }

    private var removalConfirmation: some View {
        EmptyView().alert("Remove \(installed.manifest.name) from utt?", isPresented: $removing) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                store.send(.settings(.extensionRemoveTapped(installed.id)))
                SettingsRoute.shared.open(.extensions)
            }
        } message: {
            Text("Its files go to the Trash. The program stays installed.")
        }
    }

    /// Attached to the page rather than to a row: the alert has to survive the
    /// list redrawing under it, which it does every three seconds.
    private var confirmation: some View {
        EmptyView().alert(
            confirming?.label ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
        ) {
            Button("Cancel", role: .cancel) { confirming = nil }
            Button(confirming?.label ?? "Continue") {
                if let action = confirming {
                    store.send(.settings(.extensionActionTapped(installed.id, key: action.key)))
                }
                confirming = nil
            }
        } message: {
            Text(confirming?.detail ?? "")
        }
    }

    private var daemonState: ExtensionDaemonState {
        store.settings.daemonStates[installed.id] ?? .unknown
    }

    /// What launchd says, not what the extension says about itself. A crashed daemon
    /// leaves a status file claiming it is up, and that is the one state the
    /// extension's own file cannot report.
    private var daemonDetail: String {
        switch daemonState {
        case .running: daemonState.summary
        case .stopped: "\(daemonState.summary). launchd has the job but nothing is running. Restart starts it."
        case .unknown: "\(daemonState.summary). launchd has no job by this name on this Mac, so Restart cannot help until the extension installs it."
        }
    }

    private func press(_ action: ExtensionAction) {
        guard !action.confirms else { return confirming = action }
        store.send(.settings(.extensionActionTapped(installed.id, key: action.key)))
    }

    /// Which stages this extension opted out of, named the way the pages that own them
    /// are named. It is on the page rather than silent because the alternative is a
    /// person editing a replacement rule and watching it not take effect.
    private var skipNote: String {
        let stages = installed.manifest.skipsTextStages.map(\.pageName).sorted()
        return "\(installed.manifest.name) asked for its own clips back without \(stages.joined(separator: " or ")). "
            + "Only the audio it sends itself — what you dictate is untouched."
    }

    /// The token is a credential, and handing one to an extension is a thing the user
    /// should be able to see having happened — so the page says it plainly rather
    /// than leaving it to whoever reads the values file.
    private var apiNote: String {
        settings.api.enabled
            ? "utt put the token in this extension's own settings file. Only your account can read it."
            : "utt's API is off, so this extension has no token. Turn it on under Connect › API if the extension needs one."
    }

    @ViewBuilder
    private func row(_ setting: ExtensionSetting) -> some View {
        SettingRow(setting.label, detail: setting.detail) {
            switch setting.kind {
            case .bool:
                Toggle(setting.label, isOn: binding(setting, default: false))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Palette.accent)
            case .string:
                TextField(setting.label, text: binding(setting, default: ""))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            case .number:
                TextField(setting.label, value: binding(setting, default: 0.0), format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            case .choice:
                Picker(setting.label, selection: binding(setting, default: "")) {
                    ForEach(setting.options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    /// Writes go through the store, not `@Shared`: an extension is watching its values
    /// file and has to see the change now, which a settings-file write would not
    /// reach. Same reason the API card binds this way.
    private func binding<Value>(_ setting: ExtensionSetting, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { setting.value.unwrapped as? Value ?? fallback },
            set: { newValue in
                guard let value = ExtensionValue(newValue) else { return }
                store.send(.settings(.extensionValueChanged(installed.id, key: setting.key, value: value)))
            }
        )
    }
}

private extension ExtensionValue {
    /// The scalar behind the case, for a SwiftUI control that wants a `Bool`,
    /// a `String` or a `Double`.
    var unwrapped: Any {
        switch self {
        case let .bool(flag): flag
        case let .string(text): text
        case let .number(number): number
        }
    }

    init?(_ value: Any) {
        switch value {
        case let flag as Bool: self = .bool(flag)
        case let text as String: self = .string(text)
        case let number as Double: self = .number(number)
        default: return nil
        }
    }
}

extension String {
    /// A status key as a person reads it: `lastRelay` → "Last relay". Extensions write
    /// camelCase keys, and rendering one verbatim puts "LastRelay" on the page.
    /// No dictionary and no title-casing — the key's own words, in its own order.
    var asFieldLabel: String {
        let spaced = reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        guard let first = spaced.first else { return spaced }
        return first.uppercased() + spaced.dropFirst().lowercased()
    }
}
