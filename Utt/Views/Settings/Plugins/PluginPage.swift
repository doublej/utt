import ComposableArchitecture
import SwiftUI
import UttCore

/// A page utt did not write. The controls come from the plugin's manifest, so
/// this view renders a schema rather than a fixed list of settings — the one
/// place in the app where that is true.
///
/// Everything shown here was written by another process. It is displayed, never
/// interpreted: the status block is the plugin's own words, and the settings are
/// whatever survived `PluginManifest.sanitized()`.
struct PluginPage: View {
    let store: StoreOf<AppFeature>
    let plugin: InstalledPlugin
    @Shared(.uttSettings) private var settings
    @State private var confirming: PluginAction?

    var body: some View {
        if !plugin.status.isEmpty {
            SettingsGroup("Status") {
                // Alphabetical: a JSON object has no order to preserve, and
                // inventing one would put the fields in an order the plugin
                // did not choose either.
                ForEach(plugin.status.keys.sorted(), id: \.self) { key in
                    SettingRow(key.asFieldLabel) {
                        Text(plugin.status[key] ?? "")
                            .font(Typography.metadata)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }

        if let daemon = plugin.manifest.daemon {
            SettingsGroup("Daemon") {
                SettingRow(
                    daemon.label,
                    detail: daemonDetail,
                    detailTint: daemonState == .stopped ? Palette.warning : Palette.textTertiary
                ) {
                    Button("Restart") {
                        store.send(.settings(.pluginDaemonRestartTapped(plugin.id)))
                    }
                    .font(Typography.metadata)
                }
            }
        }

        if !plugin.manifest.actions.isEmpty {
            SettingsGroup("Actions") {
                ForEach(plugin.manifest.actions) { action in
                    SettingRow(action.label, detail: action.detail) {
                        Button(action.label) { press(action) }
                            .font(Typography.metadata)
                    }
                }
            }
        }

        if plugin.settings.isEmpty {
            Card {
                Text("\(plugin.manifest.name) has no settings to change here.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
        } else {
            SettingsGroup("Settings") {
                ForEach(plugin.settings) { setting in
                    row(setting)
                }
            }
        }

        confirmation

        if plugin.manifest.wantsTranscripts || plugin.manifest.needsApi || plugin.manifest.sendsAudio {
            SettingsGroup("Access") {
                if plugin.manifest.sendsAudio {
                    SettingRow(
                        "Sends audio to be transcribed",
                        detail: "Drops clips in a folder of its own and gets the text back. Transcribed on this Mac, with your engine and your text rules. Nothing goes over the network."
                    ) {
                        Image(systemName: "waveform").foregroundStyle(Palette.textTertiary)
                    }
                }
                if plugin.manifest.wantsTranscripts {
                    SettingRow(
                        "Receives your transcripts",
                        detail: "Everything you dictate on this Mac is written to this plugin's own file as it finishes, whether or not utt keeps it in History.",
                        detailTint: Palette.textTertiary
                    ) {
                        Image(systemName: "text.quote").foregroundStyle(Palette.textTertiary)
                    }
                }
                if plugin.manifest.needsApi {
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
                    store.send(.settings(.pluginActionTapped(plugin.id, key: action.key)))
                }
                confirming = nil
            }
        } message: {
            Text(confirming?.detail ?? "")
        }
    }

    private var daemonState: PluginDaemonState {
        store.settings.daemonStates[plugin.id] ?? .unknown
    }

    /// What launchd says, not what the plugin says about itself. A crashed daemon
    /// leaves a status file claiming it is up, and that is the one state the
    /// plugin's own file cannot report.
    private var daemonDetail: String {
        switch daemonState {
        case .running: daemonState.summary
        case .stopped: "\(daemonState.summary). launchd has the job but nothing is running. Restart starts it."
        case .unknown: "\(daemonState.summary). launchd has no job by this name on this Mac, so Restart cannot help until the plugin installs it."
        }
    }

    private func press(_ action: PluginAction) {
        guard !action.confirms else { return confirming = action }
        store.send(.settings(.pluginActionTapped(plugin.id, key: action.key)))
    }

    /// The token is a credential, and handing one to a plugin is a thing the user
    /// should be able to see having happened — so the page says it plainly rather
    /// than leaving it to whoever reads the values file.
    private var apiNote: String {
        settings.api.enabled
            ? "utt put the token in this plugin's own settings file. Only your account can read it."
            : "utt's API is off, so this plugin has no token. Turn it on under Connect › API if the plugin needs one."
    }

    @ViewBuilder
    private func row(_ setting: PluginSetting) -> some View {
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
                    .frame(width: 180)
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
                .fixedSize()
            }
        }
    }

    /// Writes go through the store, not `@Shared`: a plugin is watching its values
    /// file and has to see the change now, which a settings-file write would not
    /// reach. Same reason the API card binds this way.
    private func binding<Value>(_ setting: PluginSetting, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { setting.value.unwrapped as? Value ?? fallback },
            set: { newValue in
                guard let value = PluginValue(newValue) else { return }
                store.send(.settings(.pluginValueChanged(plugin.id, key: setting.key, value: value)))
            }
        )
    }
}

private extension PluginValue {
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
    /// A status key as a person reads it: `lastRelay` → "Last relay". Plugins write
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
