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
            PatternMark(pattern: lock.pattern, size: 44)
            Spacer().frame(height: 20)
            Text("Nothing you say leaves this Mac.")
                .font(Typography.primaryRow)
            Spacer().frame(height: 6)
            Text("Speech becomes text on this machine. No account, no upload, nothing to sign in to.")
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

    /// Read from settings rather than hardcoded to ⌃fn: it is the default on a
    /// first run, but this screen is also what a re-run shows.
    private var gestureCard: some View {
        HStack(spacing: 10) {
            HotkeyGlyphs(hotkey: settings.hotkey)
            phrase.font(Typography.metadata)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.small)
        .contentSurface(radius: Radius.medium)
    }

    /// One `Text`, so the four steps wrap as a sentence rather than as four boxes.
    /// Built as an `AttributedString` because the separators are a different tint
    /// and `Text` concatenation is deprecated on macOS 26.
    private var phrase: Text {
        var result = AttributedString()
        for (index, step) in ["hold", "speak", "let go", "text at your cursor"].enumerated() {
            if index > 0 { result += tinted(" · ", Palette.textTertiary) }
            result += tinted(step, Palette.textSecondary)
        }
        return Text(result)
    }

    private func tinted(_ text: String, _ color: Color) -> AttributedString {
        var run = AttributedString(text)
        run.foregroundColor = color
        return run
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
