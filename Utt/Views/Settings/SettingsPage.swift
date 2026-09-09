import SwiftUI

/// The top of every page: the category's tile, its name, and one line on what
/// the page changes. The tile is the same mark as the sidebar's, larger, so the
/// eye lands on the page it just chose.
struct SettingsPageHeader: View {
    let tab: SettingsPanel.Tab

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.small) {
            CategoryIcon(tab.systemImage, size: 36, prominent: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(Typography.pageTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(tab.blurb)
                    .font(Typography.subtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A category's mark: a symbol on a tile. Grey until it is the current page, so
/// a column of ten stays one colour and the accent says exactly one thing.
struct CategoryIcon: View {
    let systemImage: String
    var size: CGFloat = 22
    var prominent = false

    init(_ systemImage: String, size: CGFloat = 22, prominent: Bool = false) {
        self.systemImage = systemImage
        self.size = size
        self.prominent = prominent
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(prominent ? Color.white : Palette.textSecondary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(prominent ? Palette.accent : Color.primary.opacity(0.08))
            )
            .accessibilityHidden(true)
    }
}
