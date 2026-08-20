import ComposableArchitecture
import SwiftUI

/// Screen 1: what the app does, in one gesture — and the privacy claim made
/// *before* the microphone is asked for, which is the one ordering every
/// competitor gets backwards.
struct OnboardingWelcome: View {
    @Shared(.uttSettings) private var settings
    /// Locked → unlatched → open → glint → locked. It ends sealed, which is what
    /// makes it a privacy mark rather than a "permissions granted" one — the
    /// reason it plays here and nowhere else in the flow.
    @State private var lock = OneShotPatternPlayer(
        frames: LockAnimation.frames, interval: LockAnimation.frameInterval
    )

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            // 96, not 44: at 44 the dot geometry draws 5pt lit dots, which measured
            // as the palest ink in the window — the one animated, branded element on
            // the cover screen was weaker than the 11pt caption under it.
            PatternMark(pattern: lock.pattern, size: 96)
            Spacer().frame(height: Spacing.large)
            Text("Nothing you say leaves this Mac.")
                .font(Typography.primaryRow)
            Spacer().frame(height: Spacing.extraSmall)
            Text("No account, no sign-up. Setup is five screens, about ninety seconds.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: Spacing.extraLarge)
            gestureCard
            Spacer(minLength: 0)
        }
        .padding(Spacing.medium)
        .onAppear { lock.play() }
    }

    /// A specimen, not a third telling of the gesture: the header title and subtitle
    /// have already said it, and the only thing this card can add is *which* key —
    /// read from settings rather than hardcoded to ⌃fn, because this screen is also
    /// what a re-run shows. It hugs its content so it reads as a chip rather than a
    /// 39%-filled rail.
    private var gestureCard: some View {
        HStack(spacing: Spacing.small) {
            HotkeyGlyphs(hotkey: settings.hotkey)
            Text("works in every app you type in")
                .font(Typography.metadata)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Spacing.small)
        .contentSurface(radius: Radius.medium)
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
