import ComposableArchitecture
import Foundation
import UttCore

/// Everything the one key event stream turns into: which chords the tap swallows,
/// and which action each key becomes.
///
/// Split from `AppFeature` for room, but the split is also the subject line — the
/// review keys, the hotkey and the paste-last shortcut all have to agree with each
/// other, and they only can if they are written next to each other.
extension AppFeature {
    /// Not in State because it is not `Equatable` state the UI should diff on — it
    /// is the accumulated position of a state machine.
    /// Fixed, not user-settable: it is a convenience, and every chord offered to
    /// the recorder is one more chance to shadow something the user already relies on.
    static let pasteLastHotKey = HotKey(key: .v, modifiers: [.option, .shift])

    /// Swallowed only while a transcript is waiting on the user. Bare, so ⇧⏎ and
    /// ⌘⏎ still reach the app underneath — suppression matches key *and* modifiers.
    static let reviewChords = [
        HotKey(key: .return, modifiers: []),
        HotKey(key: .escape, modifiers: [])
    ]

    fileprivate static let processor = LockIsolated(
        HotKeyProcessor(hotkey: .init(key: nil, modifiers: []))
    )
    fileprivate static let recorder = LockIsolated(HotKeyRecorder())

    /// A fresh recorder per capture: a half-entered chord must not carry into the
    /// next attempt.
    func resetRecorder() -> Effect<Action> {
        Self.recorder.setValue(HotKeyRecorder())
        return .none
    }

    /// While the settings panel is capturing a new chord, events go to the recorder
    /// instead of the processor — otherwise choosing a hotkey would also fire it.
    func handle(_ event: KeyEvent, _ state: inout State) -> Effect<Action> {
        guard !state.settings.isRecordingHotkey else {
            guard let captured = Self.recorder.withValue({ $0.process(event) }) else { return .none }
            Self.recorder.setValue(HotKeyRecorder())
            return .send(.settings(.hotkeyCaptured(captured)))
        }
        if state.transcription.pendingReview != nil, let review = Self.reviewAction(for: event) {
            return .send(.transcription(review))
        }
        if matchesPasteLast(event) { return .send(.pasteLastTapped) }
        let output = Self.processor.withValue { $0.process(keyEvent: event) }
        guard let output else { return .none }
        return .send(.transcription(.hotKey(output)))
    }

    /// ⏎ delivers the held transcript, ⎋ throws it away — bare only, matching the
    /// chords `applySuppression` swallows, so the two can never disagree about
    /// which keys the panel has taken over.
    static func reviewAction(for event: KeyEvent) -> TranscriptionFeature.Action? {
        guard event.modifiers.isEmpty, let key = event.key else { return nil }
        switch key {
        case .return: return .reviewAccepted
        case .escape: return .reviewDiscarded
        default: return nil
        }
    }

    func matchesPasteLast(_ event: KeyEvent) -> Bool {
        event.key == Self.pasteLastHotKey.key
            && event.modifiers.erasingSides() == Self.pasteLastHotKey.modifiers
    }

    /// Falls back to history, so the shortcut still works in a session that has not
    /// recorded anything yet — which is every session right after a relaunch, and
    /// every session with history turned off.
    func withLastTranscript(
        _ state: State, _ action: @escaping @Sendable (String) async -> Void
    ) -> Effect<Action> {
        guard let text = state.transcription.lastTranscript ?? transcripts.history.first?.text
        else { return .none }
        return .run { _ in await action(text) }
    }

    /// The processor is not in state, so a settings edit has to be pushed into it.
    func syncProcessor(_ state: State) -> Effect<Action> {
        syncProcessorNow(state)
        return .none
    }

    /// The suppressed chord list, derived from state in exactly one place. The
    /// review keys are **merged** with the hotkey rather than replacing it — the
    /// hotkey has to stay swallowed while a review is armed — and because the list
    /// is rebuilt from `pendingReview` after every transcription action, Return
    /// stops being swallowed the instant review ends. Nothing toggles it.
    func applySuppression(_ state: State) {
        var chords = [settings.hotkey, Self.pasteLastHotKey]
        if state.transcription.pendingReview != nil { chords += Self.reviewChords }
        keyEventMonitor.setSuppressed(chords)
    }

    func syncProcessorNow(_ state: State) {
        applySuppression(state)
        Self.processor.withValue { processor in
            processor.hotkey = settings.hotkey
            processor.minimumKeyTime = settings.minimumKeyTime
            processor.doubleTapLockEnabled = settings.doubleTapLockEnabled
            processor.useDoubleTapOnly = settings.useDoubleTapOnly
        }
    }
}
