import ComposableArchitecture
import SwiftUI
import UttCore

/// One setting, the way a settings page reads: the name on the left, what it does
/// under that in smaller type, the control on the right. The explanation is on
/// the page rather than in a tooltip because a tooltip is only read by someone
/// who already suspects there is something to know.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: () -> Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.primaryRow)
                if let detail {
                    Text(detail)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.medium)
            control()
        }
    }
}

/// The commonest row: a switch.
struct SettingToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(title, detail: detail) {
            // The label is hidden, not dropped: it is still the switch's
            // accessibility name.
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A card of rows with a hairline between each pair. The rows are read out of
/// the builder so a page can list them flat, with conditionals and `ForEach`,
/// and never place a divider by hand.
struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Card(title, spacing: Spacing.extraSmall) {
            Group(subviews: content()) { rows in
                ForEach(rows) { row in
                    row
                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

extension Shared where Value == UttSettings {
    /// A binding straight into the settings file: the way every page writes,
    /// unless the change has to reach a reducer first.
    func binding<Member>(_ keyPath: WritableKeyPath<UttSettings, Member> & Sendable) -> Binding<Member> {
        Binding(
            get: { wrappedValue[keyPath: keyPath] },
            set: { newValue in withLock { $0[keyPath: keyPath] = newValue } }
        )
    }
}
