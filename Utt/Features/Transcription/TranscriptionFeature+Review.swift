import ComposableArchitecture
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "feature.transcription")

/// The delivery half of the pipeline: what happens to a finished transcript, and
/// what the panel above the Dock says about it.
///
/// Split from the reducer rather than added to it — `TranscriptionFeature.swift`
/// owns the recording lifecycle and has no room left. Internal, not `private`,
/// because the reducer in the other file dispatches into these.
extension TranscriptionFeature {
    func transcribed(_ state: inout State, _ result: Result<String, Error>) -> Effect<Action> {
        state.recordingStartedAt = nil
        switch result {
        case let .success(raw):
            let text = settings.applyTextTransforms(to: raw)
            guard !text.isEmpty else {
                // Empty is what a too-quiet mic produces — Parakeet returns "" rather
                // than erroring — so say that instead of silently doing nothing.
                state.status = state.quietWarning
                    ? .failed("Nothing heard — your input level looks very low")
                    : .idle
                return .none
            }
            state.status = .idle
            guard settings.deliveryMode == .review else { return deliver(&state, text) }
            // Held, not pasted. No dismiss timer: a review card that vanishes on
            // its own is worse than no review at all.
            state.pendingReview = text
            return .none

        case let .failure(error):
            log.error("transcription failed: \(error.localizedDescription)")
            state.status = .failed(error.localizedDescription)
            return .none
        }
    }

    /// The only place a transcript is handed to another app. `lastTranscript` is
    /// set here and nowhere else, so "the last one" always means "the last one that
    /// actually left" — a discarded review never becomes the thing ⌥⇧V pastes.
    func deliver(_ state: inout State, _ text: String) -> Effect<Action> {
        state.lastTranscript = text
        guard settings.useClipboardPaste else {
            // Copy-only is a delivery, not a failure: the text is exactly where the
            // user asked for it to be. So it reports `true` — `pasteFinished` means
            // "it arrived", not "⌘V was posted" — which also keeps it in history.
            return .run { send in
                await pasteboard.copy(text)
                await send(.pasteFinished(true))
            }
        }
        let keepOnClipboard = settings.copyToClipboard
        return .run { send in
            await send(.pasteFinished(pasteboard.paste(text, keepOnClipboard)))
        }
    }

    func didPaste(_ state: inout State, _ pasted: Bool) -> Effect<Action> {
        guard pasted else {
            state.status = .failed("Could not paste — the text is on your clipboard")
            return .none
        }
        state.lastDeliveredAt = now
        return startDismissTimer()
    }

    func acceptReview(_ state: inout State) -> Effect<Action> {
        guard let text = state.pendingReview else { return .none }
        endReview(&state)
        return deliver(&state, text)
    }

    func discardReview(_ state: inout State) -> Effect<Action> {
        endReview(&state)
        return .none
    }

    /// The one place `pendingReview` is cleared. `AppFeature` derives the suppressed
    /// chord list from it, so every path out of review has to come through here — a
    /// leaked suppression is a Return key that is dead system-wide.
    func endReview(_ state: inout State) {
        state.pendingReview = nil
    }

    func undoLastPaste(_ state: inout State) -> Effect<Action> {
        state.lastDeliveredAt = nil
        return .merge(
            .cancel(id: CancelID.hud),
            .run { _ in await pasteboard.undo() }
        )
    }

    func dismissHUD(_ state: inout State) -> Effect<Action> {
        state.lastDeliveredAt = nil
        return .cancel(id: CancelID.hud)
    }

    /// Zero means "stay until dismissed", so there is no timer at all — not a timer
    /// with a zero delay, which would close the card before it had been read.
    func startDismissTimer() -> Effect<Action> {
        let delay = settings.hudDismissAfter
        guard delay > 0 else { return .none }
        return .run { send in
            try await Task.sleep(for: .seconds(delay))
            await send(.hudTimerExpired)
        }
        .cancellable(id: CancelID.hud, cancelInFlight: true)
    }
}
