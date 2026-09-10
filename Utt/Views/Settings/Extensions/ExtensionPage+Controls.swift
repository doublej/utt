import ComposableArchitecture
import SwiftUI
import UttCore

/// The control behind each row of an extension's settings. Its own file only
/// because the page is at the size limit; nothing here is reachable from anywhere
/// else.
extension ExtensionPage {
    @ViewBuilder
    func row(_ setting: ExtensionSetting) -> some View {
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
    func binding<Value>(_ setting: ExtensionSetting, default fallback: Value) -> Binding<Value> {
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
