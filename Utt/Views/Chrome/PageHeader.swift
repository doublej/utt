import SwiftUI

/// The top of a page: a category tile, its name, one line on what the page is
/// for, and room on the right for the page's own controls. Settings pages, the
/// history list and the permission guide all open this way, so moving between
/// them never changes what a title looks like.
struct PageHeader<Trailing: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ systemImage: String, title: String, subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.small) {
            CategoryIcon(systemImage, size: 36, prominent: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.pageTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(subtitle)
                    .font(Typography.subtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.small)
            trailing()
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.xxs)
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
