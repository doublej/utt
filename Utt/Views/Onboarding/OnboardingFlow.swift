import ComposableArchitecture
import SwiftUI

/// The first run, in five screens and about ninety seconds.
///
/// Nothing inside it blocks: every screen's primary button is live from the moment
/// it appears, and the only ways out are Skip in the header and Done on the last
/// screen. Both count as finishing — a user who skipped chose to, and the main
/// window's banner is already the safety net for whatever they skipped past.
///
/// No reducer. `step` is view state, and everything else the flow renders already
/// lives in `AppFeature` or in `@Shared(.uttSettings)`.
struct OnboardingFlow: View {
    let store: StoreOf<AppFeature>
    @Environment(\.dismiss) private var dismiss
    @Shared(.uttSettings) private var settings
    @State private var step: Step = .welcome
    /// Owned here rather than in screen 5 so the footer can read it — the counter
    /// row sits below the divider, and the screen it describes is above it.
    @State private var practice = PracticeProgress()

    /// Raw values are the order, and the order is the argument: Hotkey sits after
    /// Model so the practice rep drills the key the user just confirmed rather than
    /// the one they are about to change.
    enum Step: Int, CaseIterable {
        case welcome, permissions, model, hotkey, practice
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            screen.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 460, height: 580)
        // Every way out lands here, which is why the finishing happens here rather
        // than in `finish()`: Esc and the sheet's own dismissal never pass through a
        // button, and a flow that closed without recording it would open again on the
        // next launch. Leaving on any screen also has to drop the floating drag card,
        // not just leaving screen 2 — the sheet is what was holding it up.
        .onDisappear {
            $settings.withLock { $0.hasCompletedOnboarding = true }
            DragToSettingsPanel.shared.hide()
        }
    }

    @ViewBuilder private var screen: some View {
        switch step {
        case .welcome: OnboardingWelcome()
        case .permissions: OnboardingPermissions(store: store)
        case .model: OnboardingModel(store: store)
        case .hotkey: OnboardingHotkey(store: store)
        case .practice:
            OnboardingPractice(store: store, progress: $practice) { step = .permissions }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            UttMark(size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(Typography.sectionTitle)
                Text(step.subtitle)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.small)
            // Not on the last screen: Done *is* the leave there, so a second exit
            // with a different label promises content that does not exist.
            if step != .practice {
                Button("Skip") { finish() }
                    .buttonStyle(.link)
                    .font(Typography.hint)
            }
        }
        .padding(Spacing.medium)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            statusRow.frame(height: Spacing.medium, alignment: .leading)
            HStack(spacing: Spacing.extraSmall) {
                StepDots(current: step)
                Spacer()
                if step != .welcome {
                    Button("Back") { back() }
                }
                Button(step.primaryLabel) { advance() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.medium)
    }

    /// One slot, always reserved, so the divider above the footer stays put. Without
    /// it the band slid 48pt across the wizard — including a jump under the user's
    /// hands on screen 5. The two rows can never both appear: a rep needs a
    /// transcript, which needs a ready model, which is what hides the strip.
    ///
    /// The strip still stays off screen 3, where the model card shows the same
    /// percentage with a bigger bar — with the slot reserved that no longer costs a
    /// jump.
    @ViewBuilder private var statusRow: some View {
        if step == .practice, practice.reps > 0 {
            practiceStatus
        } else if !store.model.isReady, step != .model {
            ModelStrip(state: store.model)
        } else {
            Color.clear
        }
    }

    private var practiceStatus: some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(systemName: practice.isComplete ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(practice.isComplete ? Palette.success : Palette.textTertiary)
            Text(practice.isComplete
                ? "utt is set up. Nothing else to do."
                : "One down, one to go.")
                .font(Typography.metadata)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Just the dismissal. `isFirstRun` is derived from "no settings file *content*
    /// yet" — the path itself is touched into being at store init — and the file
    /// fills the moment anything writes to it, so the durable flag is what decides
    /// whether this ever opens again, and `onDisappear` sets it for this route and
    /// every other one.
    private func finish() { dismiss() }
}

extension OnboardingFlow.Step {
    /// State-neutral, all five. `title` is static on the enum with no store to read,
    /// and a header that narrates progress goes stale in place: the download often
    /// finishes before the user has clicked this far, and on a re-run the model is
    /// always already loaded — so `.model` names what the screen is about rather than
    /// what it is currently doing, and the card below it carries the state.
    var title: String {
        switch self {
        case .welcome: "Hold a key, talk, let go"
        case .permissions: "Let macOS hear you out"
        case .model: "Your Mac does the listening"
        case .hotkey: "Your hotkey"
        case .practice: "Say something"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "The words land wherever your cursor is."
        case .permissions: "Three switches, once. Nothing you say leaves this Mac."
        case .model: "One download, then utt never needs the network."
        case .hotkey: "utt picked one already. Keep it or change it here."
        case .practice: "Two rounds and you are done."
        }
    }

    var primaryLabel: String {
        switch self {
        case .welcome: "Get started"
        case .practice: "Done"
        default: "Continue"
        }
    }
}

/// One line of model progress, on every screen until the weights are in memory.
/// `ModelRow` in settings is the full treatment; this is the ambient version, and
/// it never gates anything — `AppFeature.start` began the fetch before the sheet
/// had painted.
private struct ModelStrip: View {
    let state: AppFeature.ModelState

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            KickerLabel(text: "Model")
            Text(caption)
                .font(Typography.metadata)
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: Spacing.small)
            trailing
        }
    }

    /// No engine name: the strip has no idea which one is loading, and naming
    /// Parakeet in front of a WhisperKit download is worse than naming nothing.
    /// `KickerLabel` already says "Model".
    private var caption: String {
        switch state {
        case .idle: "Queued"
        case let .downloading(fraction): "Downloading \(Int(fraction * 100))%"
        case .loading: "Compiling for this Mac"
        case .ready: "Ready"
        case let .failed(message): message
        }
    }

    private var tint: Color {
        if case .failed = state { return Palette.warning }
        return Palette.textSecondary
    }

    /// The two phases are not one percentage: the download reports a real fraction,
    /// the CoreML compile after it reports nothing at all. A bar stuck at 100% for
    /// half a minute is worse than a spinner that never claimed to know.
    @ViewBuilder private var trailing: some View {
        switch state {
        case let .downloading(fraction):
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Palette.accent)
                .frame(width: 72)
        case let .loading(since):
            HStack(spacing: Spacing.xxs) {
                ProgressView().controlSize(.small)
                ElapsedTimer(
                    startedAt: since, font: Typography.monoSmall, tint: Palette.textSecondary
                )
            }
        default:
            EmptyView()
        }
    }
}

/// Filled cumulatively, so the row reads as progress rather than as a carousel.
private struct StepDots: View {
    let current: OnboardingFlow.Step

    var body: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingFlow.Step.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= current.rawValue
                        ? Palette.accent
                        : Palette.textTertiary.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingFlow.Step.allCases.count)")
    }
}
