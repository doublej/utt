import ComposableArchitecture
import SwiftUI

/// Screen 4: show the key, make it changeable in place, and mention the one
/// gesture nothing else in the app mentions.
///
/// utt ships a default, so this is a confirmation rather than a decision — which
/// is a large part of why five screens fit in ninety seconds. The recorder is
/// `HotkeyRow`'s, unchanged; only the cap size differs, because this is the one
/// screen whose subject is the key itself.
struct OnboardingHotkey: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    private var capturing: Bool { store.settings.isRecordingHotkey }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            hotkeyCard
            // Tight above, loose below. The paragraph explains the card it sits under;
            // with equal gaps on both sides it read as belonging to neither surface.
            Text("""
                Anything you can hold works — even a modifier on its own. Every other \
                key keeps doing what it always did.
                """)
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Spacing.medium)
            doubleTapCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.large)
        // While the recorder is armed every key event goes to it instead of the
        // processor. Walking off this screen mid-capture would leave the next
        // screen's hotkey dead and the keyboard swallowed.
        .onDisappear {
            if capturing { store.send(.settings(.hotkeyRecordingToggled)) }
        }
    }

    private var hotkeyCard: some View {
        VStack(spacing: Spacing.medium) {
            if capturing {
                Text("Press the keys…")
                    .font(Typography.primaryRow)
                    .foregroundStyle(Palette.accent)
                    .frame(height: 34)
            } else {
                // 27, so the cap comes out at 34 (`minHeight: size + 7`) — the
                // artboard's `cap-lg`. On the one screen whose subject is the key, the
                // key should be the biggest thing on it; at 20 it was 1.5× the ambient
                // cap instead of 1.9×.
                HotkeyGlyphs(hotkey: settings.hotkey, size: 27)
                    .frame(height: 34)
            }
            Button(capturing ? "Cancel" : "Change") {
                store.send(.settings(.hotkeyRecordingToggled))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(
            EdgeInsets(
                top: Spacing.extraLarge, leading: Spacing.small, bottom: Spacing.large,
                trailing: Spacing.small
            )
        )
        .contentSurface(radius: Radius.medium)
    }

    /// Copy only, no control: the gesture is on by default and `doubleTapLockEnabled`
    /// has a toggle in Settings. This is the only place in the app that says it exists.
    private var doubleTapCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Double-tap to lock recording on")
                .font(Typography.primaryRow)
            Text("For a long stretch you would rather not hold. Tap twice, talk, tap once to stop.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(radius: Radius.medium)
    }
}
