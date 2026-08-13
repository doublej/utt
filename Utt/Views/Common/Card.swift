import SwiftUI

/// Titled content surface. Never nest one inside another — stacked translucency is
/// what the Design notes call the "muddy 2005 UI" look.
struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.bottom, 2)
            }
            VStack(alignment: .leading, spacing: Spacing.small) {
                content()
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentSurface(radius: Radius.medium)
        }
    }
}

/// Centered placeholder for an empty list. utty had one of these per feed; utt has
/// one list, so it takes its copy as parameters.
struct EmptyState: View {
    let systemImage: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: Spacing.extraSmall) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text(title)
                .font(Typography.primaryRow)
                .foregroundStyle(Palette.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.large)
    }
}
