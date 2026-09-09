import ComposableArchitecture
import SwiftUI

/// Screen 1: what the app does, in three facts — and the privacy claim made
/// *before* the microphone is asked for, which is the one ordering every
/// competitor gets backwards. The lock animation that makes the claim plays on
/// the rail, where the mark lives on every screen.
struct OnboardingWelcome: View {
    @Shared(.uttSettings) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Fact("keyboard", title: "Hold a key and talk") {
                Text("Let go, and the words are typed wherever your cursor is. Every app you type in.")
                // Read from settings rather than hardcoded to ⌃fn, because this screen
                // is also what a re-run shows.
                HotkeyGlyphs(hotkey: settings.hotkey)
                    .padding(.top, Spacing.xxs)
            }
            Fact("lock.shield", title: "Nothing you say leaves this Mac") {
                Text("The model runs here. No account, no sign-up, and no network once it is downloaded.")
            }
            Fact("timer", title: "About ninety seconds") {
                Text("Three permissions, one download, one practice run.")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.large)
        .padding(.top, Spacing.small)
    }
}

/// One thing worth knowing before anything is asked for: the category tile the
/// settings use, a title, and a line under it.
private struct Fact<Detail: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder let detail: () -> Detail

    init(_ systemImage: String, title: String, @ViewBuilder detail: @escaping () -> Detail) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            CategoryIcon(systemImage, size: 32)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(Typography.primaryRow)
                detail()
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Draws one dot-matrix frame. `UttMark` always renders whatever the shared
/// driver is on; the lock sequence has its own player and needs its own canvas.
/// Everything else — cell geometry, lit and unlit radii — comes from `DotMatrix`.
struct PatternMark: View {
    let pattern: Set<Int>
    var size: CGFloat = 44
    var tint: Color = Palette.accent

    var body: some View {
        Canvas { context, canvasSize in
            for index in 0..<36 {
                let lit = pattern.contains(index)
                context.fill(
                    Path(ellipseIn: DotMatrix.rect(for: index, size: canvasSize.width, lit: lit)),
                    with: .color(lit ? tint : Color.primary.opacity(0.28))
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
