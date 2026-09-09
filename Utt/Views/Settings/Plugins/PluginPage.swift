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

        if plugin.settings.isEmpty {
            Card {
                Text("\(plugin.manifest.name) has not asked for any settings.")
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

        if plugin.manifest.needsApi {
            Card {
                Text(apiNote)
                    .font(Typography.hint)
                    .foregroundStyle(settings.api.enabled ? Palette.textTertiary : Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The token is a credential, and handing one to a plugin is a thing the user
    /// should be able to see having happened — so the page says it plainly rather
    /// than leaving it to whoever reads the values file.
    private var apiNote: String {
        settings.api.enabled
            ? "\(plugin.manifest.name) can reach utt's API. Its access token is in the plugin's own settings file, readable only by your account."
            : "\(plugin.manifest.name) uses utt's API, which is off. Turn it on under Connect › API, or this plugin cannot send audio here."
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

private extension String {
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
