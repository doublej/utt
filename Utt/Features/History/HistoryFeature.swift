import ComposableArchitecture
import Foundation
import UttCore

/// Past transcripts: recording them, re-pasting them, throwing them away.
///
/// The list itself lives in `@Shared(.uttHistory)` rather than in this feature's
/// state, so the menu bar can show the last transcript without this feature being
/// on screen.
@Reducer
struct HistoryFeature {
    @ObservableState
    struct State: Equatable {
        var searchText = ""
        /// Set when the user asks to clear everything, so the view can confirm
        /// before an irreversible delete.
        var confirmingClear = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        /// Recorded after a transcript has actually been delivered.
        case record(text: String, duration: TimeInterval, app: AppIdentity?)
        case copyTapped(Transcript.ID)
        case deleteTapped(Transcript.ID)
        case clearTapped
        case clearConfirmed
        case clearDismissed
    }

    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.date.now) var now
    @Shared(.uttHistory) var history
    @Shared(.uttSettings) var settings

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding: return .none
            case let .record(text, duration, app): return record(text, duration, app)
            case let .copyTapped(id): return copy(id)
            case let .deleteTapped(id): $history.withLock { $0.remove(id) }; return .none
            case .clearTapped: state.confirmingClear = true; return .none
            case .clearDismissed: state.confirmingClear = false; return .none
            case .clearConfirmed:
                state.confirmingClear = false
                $history.withLock { $0.history.removeAll() }
                return .none
            }
        }
    }

    /// Case-insensitive substring match. Deliberately not a fuzzy or token search:
    /// people look for a phrase they remember saying.
    func filtered(_ state: State) -> [Transcript] {
        let query = state.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return history.history }
        return history.history.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
}

private extension HistoryFeature {
    func record(_ text: String, _ duration: TimeInterval, _ app: AppIdentity?) -> Effect<Action> {
        guard settings.saveTranscriptionHistory else { return .none }
        let entry = Transcript(
            timestamp: now,
            text: text,
            duration: duration,
            sourceAppBundleID: app?.bundleID,
            sourceAppName: app?.name
        )
        $history.withLock { $0.record(entry, cap: settings.maxHistoryEntries) }
        return .none
    }

    func copy(_ id: Transcript.ID) -> Effect<Action> {
        guard let entry = history.history.first(where: { $0.id == id }) else { return .none }
        return .run { _ in await pasteboard.copy(entry.text) }
    }
}
