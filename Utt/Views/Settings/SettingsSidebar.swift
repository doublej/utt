import SwiftUI

/// The category column. Three labelled groups, a tile per category, the current
/// one lit. Plain buttons rather than a `List`: the panel already owns the
/// scrolling, and a `List` inside a `ScrollView` fights it for the wheel.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPanel.Tab

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            ForEach(SettingsPanel.Tab.groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, Spacing.extraSmall)
                        .padding(.bottom, Spacing.xxs)
                    ForEach(group.tabs) { tab in
                        SidebarRow(tab: tab, selected: tab == selection) { selection = tab }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Spacing.xxs)
        .padding(.trailing, Spacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings categories")
    }
}

private struct SidebarRow: View {
    let tab: SettingsPanel.Tab
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Spacing.extraSmall) {
                CategoryIcon(tab.systemImage, size: 22, prominent: selected)
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.07 : hovering ? 0.035 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
