import ComposableArchitecture
import SwiftUI
import UttCore

/// One card, four things it can say. The card is `chromeGlass` in a rounded rect so
/// it reads as the same object as the collapsed pill rather than as a notification
/// from somewhere else.
struct TranscriptHUDView: View {
    let store: StoreOf<AppFeature>
    /// Called when the card appears or disappears: the panel behind it is only
    /// allowed to take clicks while there is something to click.
    let onVisibilityChanged: (Bool) -> Void

    @Shared(.uttSettings) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The live words and the finished transcript share a place on the card, so the
    /// first pass travels to where the real text lands as it resolves into it.
    @Namespace private var words

    enum Phase: Equatable {
        case recording
        case transcribing
        /// Held, waiting on ⏎ or ⎋.
        case review(ProcessedTranscript)
        /// Already pasted; this is the receipt.
        case delivered(ProcessedTranscript)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let phase {
                card(phase)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.smooth(duration: 0.3), value: phase)
        .onChange(of: phase == nil) { _, isEmpty in onVisibilityChanged(!isEmpty) }
    }

    /// Review outranks everything: a transcript waiting on the user is the only
    /// thing on screen that the rest of the machine is blocked on. An extension's
    /// own dictation has no card at all — that extension shows it.
    private var phase: Phase? {
        guard settings.showTranscriptHUD, store.transcription.owner == nil else { return nil }
        let transcription = store.transcription
        if let pending = transcription.pendingReview { return .review(pending) }
        if transcription.isRecording { return .recording }
        if transcription.status == .transcribing { return .transcribing }
        if transcription.lastDeliveredAt != nil, let last = transcription.lastTranscript {
            return .delivered(last)
        }
        return nil
    }

    /// Recording and transcribing are one branch, and review and delivered another,
    /// so the words inside keep their identity across the step: the live words do not
    /// write themselves in again when the spinner appears. Crossing between the two
    /// branches is the first pass resolving into the real transcript.
    @ViewBuilder
    private func card(_ phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            switch phase {
            case .recording, .transcribing:
                working(phase)
                    .transition(ResolveTransition(reduceMotion: reduceMotion))
            case let .review(transcript), let .delivered(transcript):
                result(transcript, phase: phase)
                    .transition(ResolveTransition(reduceMotion: reduceMotion))
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chromeGlass(radius: Radius.large)
    }

    // MARK: - States

    /// The live words are kept up while the real model works: the words the person
    /// was just watching should not blink out before the transcript replaces them.
    private func working(_ phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                if phase == .recording {
                    CompactVuMeter(level: store.transcription.meterLevel, active: true)
                    Text("Listening")
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    ElapsedTimer(startedAt: store.transcription.recordingStartedAt)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Transcribing…")
                        .font(Typography.label)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                }
            }
            live
        }
    }

    /// The live recogniser's words, drawn as provisional — dimmer than a finished
    /// transcript, in the same mono face, so the eye reads it as the same text
    /// arriving rather than as a different thing that will be replaced.
    @ViewBuilder
    private var live: some View {
        let words = store.transcription.liveWords
        if !words.isEmpty {
            WritingText(text: words)
                .font(Typography.mono)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .matchedGeometryEffect(id: "words", in: self.words)
                .transition(.opacity)
        }
    }

    private func result(_ transcript: ProcessedTranscript, phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            finished(transcript)
            if case .review = phase {
                HStack(spacing: Spacing.small) {
                    target
                    Spacer()
                    KeyAction(cap: "⏎", title: "Paste") {
                        store.send(.transcription(.reviewAccepted))
                    }
                    KeyAction(cap: "esc", title: "Discard") {
                        store.send(.transcription(.reviewDiscarded))
                    }
                }
            } else {
                cleanupNote(transcript)
                HStack(spacing: Spacing.small) {
                    target
                    Spacer()
                    plain("Undo") { store.send(.transcription(.undoLastPaste)) }
                    plain("Copy") { store.send(.copyLastTapped) }
                    plain("Add rule") { addRule() }
                    plain("Dismiss") { store.send(.transcription(.hudDismissed)) }
                }
            }
        }
    }

    // MARK: - Pieces

    /// Cleanup was on and did not happen. Here and nowhere else: interrupting at
    /// paste time, or putting anything in the text stream, breaks the one promise
    /// the app makes about what reaches the cursor.
    @ViewBuilder
    private func cleanupNote(_ transcript: ProcessedTranscript) -> some View {
        if let reason = transcript.cleanupSkipped {
            note(reason.sentence)
        }
    }

    /// The finished text, and — only when a stage rewrote it — what was heard.
    ///
    /// Not on every dictation: most transcripts come out of the pipeline unchanged
    /// or changed trivially, and a before-and-after every time is noise the eye
    /// learns to skip. The finished text keeps the mono face and the full size; the
    /// heard line is metadata, under it, one line, with the rest on hover.
    @ViewBuilder
    private func finished(_ result: ProcessedTranscript) -> some View {
        transcript(result.text)
        if result.changed {
            note("heard: \(result.raw)").lineLimit(1).help(result.raw)
        }
    }

    /// Three lines and no more. A minute of dictation must not produce a panel that
    /// covers the document it was dictated into; the whole text is on hover.
    private func transcript(_ text: String) -> some View {
        Text(text)
            .font(Typography.mono)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .matchedGeometryEffect(id: "words", in: words)
            .help(text)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typography.metadata)
            .foregroundStyle(Palette.textTertiary)
    }

    @ViewBuilder
    private var target: some View {
        if let name = store.transcription.deliveryTarget?.name {
            Text("→ \(name)")
                .font(Typography.metadata)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func plain(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Typography.metadata)
            .foregroundStyle(Palette.textSecondary)
    }

    /// Appends the blank rule and brings the window up on Replacements, where the
    /// bench above it shows what the rule does. Offered on the delivered card only:
    /// activating utt while a review is armed would repoint the paste at utt itself.
    private func addRule() {
        $settings.withLock {
            $0.wordRemappings.append(WordRemapping(match: "", replacement: ""))
        }
        store.send(.transcription(.hudDismissed))
        SettingsRoute.shared.open(.replacements)
    }
}

/// A key cap and what it does. The panel never takes focus, so the keys are the
/// real interface and the button is the affordance that says so.
private struct KeyAction: View {
    let cap: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Text(cap)
                    .font(Typography.monoSmall)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.surfaceSecondary)
                    )
                Text(title)
                    .font(Typography.metadata)
            }
            .foregroundStyle(Palette.textPrimary)
        }
        .buttonStyle(.plain)
    }
}
