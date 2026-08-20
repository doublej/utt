import ComposableArchitecture
import SwiftUI

/// What two real reps add up to. Words over *audio* duration, not hold duration:
/// the hold includes fumbling for the key, which is not what anyone means by how
/// fast they talk. Averaged over both reps, because a rate computed from one
/// three-second utterance is noise.
struct PracticeProgress: Equatable {
    var reps = 0
    var words = 0
    var seconds: TimeInterval = 0

    var isComplete: Bool { reps >= 2 }

    var wordsPerMinute: Int? {
        guard seconds > 0, words > 0 else { return nil }
        return Int(Double(words) / (seconds / 60))
    }
}

/// Screen 5: two hold–speak–release reps before the sheet closes, ending on a
/// measured number rather than a checkmark.
///
/// This is the only screen that can catch a dead event tap, a mic on the wrong
/// device, or a missing paste grant *before* the user's first real attempt in a
/// real document. The field is a real focused `TextEditor` and the paste is not
/// simulated — utt posts ⌘V into whatever is frontmost, which is this sheet, so
/// the Accessibility grant is genuinely exercised.
///
/// Nothing blocks. Done is live from the moment the screen appears; two reps is
/// the invitation, never a gate.
struct OnboardingPractice: View {
    let store: StoreOf<AppFeature>
    @Binding var progress: PracticeProgress
    let onFix: () -> Void

    @Shared(.uttSettings) private var settings
    @State private var typed = ""
    @FocusState private var focused: Bool

    private var transcription: TranscriptionFeature.State { store.transcription }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            instruction
            prompt
            field
            meter
            Spacer(minLength: 0)
            if let missing = store.missingPermissions.first { blockedBanner(for: missing) }
        }
        .padding(Spacing.medium)
        .onAppear { focused = true }
        // A rep counts when a transcript actually *landed*, which is what this
        // screen exists to prove. `lastTranscript` alone would also count a paste
        // that failed, and would miss two identical reps.
        .onChange(of: transcription.lastDeliveredAt) { _, delivered in
            guard delivered != nil else { return }
            progress.reps += 1
            progress.words += transcription.lastTranscript?.split(separator: " ").count ?? 0
            progress.seconds += transcription.lastDuration
        }
    }

    private var instruction: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("Hold").font(Typography.primaryRow)
            HotkeyGlyphs(hotkey: settings.hotkey)
            Text("and start talking. Let go when you're done.")
                .font(Typography.primaryRow)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The only moving part on the screen. Deliberately `surfaceSecondary` rather
    /// than a content surface: the field below it is one, and surfaces never nest.
    private var prompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            KickerLabel(text: kicker)
            line
                .font(Typography.primaryRow)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfaceSecondary)
        )
    }

    private var kicker: String {
        switch progress.reps {
        case 0: "Try saying"
        case 1: "Round two"
        default: "Nice"
        }
    }

    /// A suggestion, not a script. It exercises the casing and punctuation Parakeet
    /// supplies that the user never spoke — free dictation reaches the same state,
    /// and the field takes typing, so a broken mic is never a trap.
    private var line: Text {
        switch progress.reps {
        case 0: Text("\"This is my first transcript, and it never left the Mac.\"")
        case 1: Text("Say anything you like — a note to yourself, a line to a colleague.")
        default: payoff
        }
    }

    private var payoff: Text {
        guard let wordsPerMinute = progress.wordsPerMinute else {
            return Text("Two down — that is the whole thing.")
        }
        // On the type scale, not above it. utt has no display type anywhere, and a
        // one-off 28pt hero number is how a native surface starts reading as a
        // landing page.
        let rate = Text("\(wordsPerMinute)").foregroundStyle(Palette.accent)
        return Text("You dictated at \(rate) words per minute.")
    }

    /// Accumulates across both reps, because that is what actually happens: the
    /// second paste lands after the first text, exactly as it would in a document.
    private var field: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            ZStack(alignment: .topLeading) {
                if typed.isEmpty {
                    Text("your words land here")
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $typed)
                    .font(Typography.primaryRow)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
            }
            .frame(height: 96)
            if case let .failed(message) = transcription.status {
                Text(message)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(radius: Radius.medium)
    }

    private var meter: some View {
        HStack(spacing: Spacing.small) {
            RecorderStatePill(state: RecorderState(transcription.status))
            VuMeter(level: transcription.meterLevel, active: transcription.isRecording)
        }
    }

    /// Whichever grant is missing, not just the hotkey one: a denied mic reads as
    /// silence and a denied paste reads as a paste that did nothing, and this is the
    /// screen that exists so neither can fail without saying why. `missingPermissions`
    /// arrives in `Permission.allCases` order, which is most-fatal-first, so the first
    /// one is the one to name. Same string the main window's banner builds, same
    /// amber treatment.
    private func blockedBanner(for permission: Permission) -> some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
            Text("\(permission.title) is off. Turn it on \(permission.rationale).")
                .font(Typography.metadata)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.extraSmall)
            Button("Fix") { onFix() }
                .font(Typography.metadata)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Palette.warning.opacity(0.12))
        )
    }
}
