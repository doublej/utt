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

    enum Phase: Equatable {
        case recording
        case transcribing
        /// Held, waiting on ⏎ or ⎋.
        case review(String)
        /// Already pasted; this is the receipt.
        case delivered(String)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let phase {
                card(phase)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.smooth(duration: 0.2), value: phase)
        .onChange(of: phase == nil) { _, isEmpty in onVisibilityChanged(!isEmpty) }
    }

    /// Review outranks everything: a transcript waiting on the user is the only
    /// thing on screen that the rest of the machine is blocked on.
    private var phase: Phase? {
        guard settings.showTranscriptHUD else { return nil }
        let transcription = store.transcription
        if let pending = transcription.pendingReview { return .review(pending) }
        if transcription.isRecording { return .recording }
        if transcription.status == .transcribing { return .transcribing }
        if transcription.lastDeliveredAt != nil, let text = transcription.lastTranscript {
            return .delivered(text)
        }
        return nil
    }

    @ViewBuilder
    private func card(_ phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            switch phase {
            case .recording: listening
            case .transcribing: transcribing
            case let .review(text): review(text)
            case let .delivered(text): delivered(text)
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chromeGlass(radius: Radius.large)
    }

    // MARK: - States

    private var listening: some View {
        HStack(spacing: Spacing.small) {
            CompactVuMeter(level: store.transcription.meterLevel, active: true)
            Text("Listening")
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            ElapsedTimer(startedAt: store.transcription.recordingStartedAt)
        }
    }

    private var transcribing: some View {
        HStack(spacing: Spacing.small) {
            ProgressView().controlSize(.small)
            Text("Transcribing…")
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
        }
    }

    private func review(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            transcript(text)
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
        }
    }

    private func delivered(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            transcript(text)
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

    // MARK: - Pieces

    /// Three lines and no more. A minute of dictation must not produce a panel that
    /// covers the document it was dictated into; the whole text is on hover.
    private func transcript(_ text: String) -> some View {
        Text(text)
            .font(Typography.mono)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .help(text)
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

    /// Appends the blank rule and brings the window up on the Text tab, where the
    /// bench under it shows what the rule does. Offered on the delivered card only:
    /// activating utt while a review is armed would repoint the paste at utt itself.
    private func addRule() {
        $settings.withLock {
            $0.wordRemappings.append(WordRemapping(match: "", replacement: ""))
        }
        store.send(.transcription(.hudDismissed))
        SettingsRoute.shared.open(.text)
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
