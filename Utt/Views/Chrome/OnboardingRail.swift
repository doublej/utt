import SwiftUI

/// The dark left third of the walkthrough: the mark, large, and the five steps as
/// a rail. It is the app icon's ground under the app icon's dots, so the first
/// thing a new user looks at is the thing they will later find in the Dock.
///
/// Rendered in the dark scheme whatever the window is in, which is what lets the
/// wordmark, the kicker and `.secondary` text draw themselves correctly on it.
struct OnboardingRail: View {
    let step: OnboardingFlow.Step
    /// Locked → unlatched → open → glint → locked. Plays once, on the welcome
    /// screen only: it ends sealed, which is what makes it a privacy mark rather
    /// than a "permissions granted" one.
    @State private var lock = OneShotPatternPlayer(
        frames: LockAnimation.frames, interval: LockAnimation.frameInterval
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mark
            Spacer(minLength: Spacing.large)
            steps
            Spacer().frame(height: Spacing.extraLarge)
            UttWordmark(size: 13)
        }
        .padding(Spacing.large)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.lcdGround)
        .environment(\.colorScheme, .dark)
        .onAppear { if step == .welcome { lock.play() } }
    }

    @ViewBuilder private var mark: some View {
        if step == .welcome {
            PatternMark(pattern: lock.pattern, size: 96)
        } else {
            UttMark(size: 96, hotCore: 0.3)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(OnboardingFlow.Step.allCases, id: \.self) { item in
                row(item)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingFlow.Step.allCases.count): \(step.railTitle)")
    }

    private func row(_ item: OnboardingFlow.Step) -> some View {
        let current = item == step
        let done = item.rawValue < step.rawValue
        return HStack(spacing: Spacing.small) {
            Text(String(format: "%02d", item.rawValue + 1))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(current ? Palette.accent : done ? Palette.lcdGreen : .secondary)
            Text(item.railTitle)
                .font(.system(size: 13, weight: current ? .semibold : .regular))
                .foregroundStyle(current ? .primary : .secondary)
            Spacer(minLength: 0)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.lcdGreen)
            }
        }
        .opacity(current || done ? 1 : 0.55)
    }
}
