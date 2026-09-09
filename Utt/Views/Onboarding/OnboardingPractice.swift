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
            // Four items, one gap value, no grouping. The instruction is a heading for
            // everything below it and gets 16; the meter is the field's own "your mic
            // is live" readout and gets 8.
            instruction
                .padding(.bottom, Spacing.xxs)
            prompt
            field
            meter
                .padding(.top, -Spacing.xxs)
            Spacer(minLength: 0)
            if let missing = store.missingPermissions.first { blockedBanner(for: missing) }
        }
        .padding(.horizontal, Spacing.large)
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
        // `.center`, not `.firstTextBaseline`: a view with no text baseline has its
        // bottom edge used as one, which floated the caps ~5pt above the line of type.
        HStack(spacing: Spacing.xxs) {
            Text("Hold").font(Typography.primaryRow)
            HotkeyGlyphs(hotkey: settings.hotkey)
            Text("and start talking. Let go when you are done.")
                .font(Typography.primaryRow)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The only moving part on the screen. Deliberately `surfaceSecondary` rather
    /// than a content surface: the field below it is one, and surfaces never nest.
    private var prompt: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
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
        default: "Two for two"
        }
    }

    /// A suggestion, not a script. It exercises the casing and punctuation Parakeet
    /// supplies that the user never spoke — free dictation reaches the same state,
    /// and the field takes typing, so a broken mic is never a trap.
    ///
    /// What it deliberately is not: a privacy claim. Four screens of those have
    /// already been granted, downloaded and believed, and the user's first-ever
    /// transcript should be theirs rather than utt's own marketing read aloud in
    /// their voice.
    private var line: Text {
        switch progress.reps {
        case 0: Text("\u{201C}Testing, one two three. If you can read this, the mic works.\u{201D}")
        case 1: Text("Say anything you like — a note to yourself, a line to a colleague.")
        default: payoff
        }
    }

    private var payoff: Text {
        guard let wordsPerMinute = progress.wordsPerMinute else {
            return Text("Two down. That is the whole app.")
        }
        // On the type scale, not above it. utt has no display type anywhere, and a
        // one-off 28pt hero number is how a native surface starts reading as a
        // landing page.
        let rate = Text("\(wordsPerMinute)").foregroundStyle(Palette.accent)
        // The comparison is what turns the number into a reason to keep the app, but
        // `wordsPerMinute` has no floor and one fumbled rep can land under typing
        // speed. Below 50 the number stands on its own rather than losing the
        // argument at the moment the flow is trying to win it.
        guard wordsPerMinute >= 50 else {
            return Text("You dictated at \(rate) words per minute.")
        }
        return Text("You dictated at \(rate) words per minute — most people type at about 40.")
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
                        // Matched to `TextEditor`'s own AppKit insets so the
                        // placeholder sits exactly where the caret will. Not tokens.
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
        .padding(Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.warning.opacity(0.12))
        )
    }
}
