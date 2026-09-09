import ComposableArchitecture
import SwiftUI
import UttCore

/// Past transcripts, newest first. utty's equivalent feed had a second tab for
/// logs; utt writes to the unified log instead, where Console can filter it.
struct HistoryList: View {
    @Bindable var store: StoreOf<AppFeature>
    @Shared(.uttHistory) private var history
    @Shared(.uttSettings) private var settings

    private var entries: [Transcript] {
        let query = store.history.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return history.history }
        return history.history.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var emptyHint: String {
        "Hold \(settings.hotkey.displayString) and speak — the text lands wherever your cursor is."
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if entries.isEmpty {
                EmptyState(
                    systemImage: history.history.isEmpty ? "waveform" : "magnifyingglass",
                    title: history.history.isEmpty ? "No transcripts yet" : "No matches",
                    subtitle: history.history.isEmpty ? emptyHint : nil
                )
            } else {
                list
            }
        }
        .confirmationDialog(
            "Delete all \(history.history.count) transcripts?",
            isPresented: confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { store.send(.history(.clearConfirmed)) }
            Button("Cancel", role: .cancel) { store.send(.history(.clearDismissed)) }
        } message: {
            Text("This cannot be undone.")
        }
    }

    /// `AppFeature.Action` is not `BindableAction`, so a child binding cannot be
    /// derived with `$store.history.…` — it has to be routed through the child's
    /// own binding action explicitly.
    private var searchText: Binding<String> {
        Binding(
            get: { store.history.searchText },
            set: { store.send(.history(.binding(.set(\.searchText, $0)))) }
        )
    }

    /// The dialog only ever closes from here, so the setter handles dismissal and
    /// the confirm button sends its own action.
    private var confirmingClear: Binding<Bool> {
        Binding(
            get: { store.history.confirmingClear },
            set: { if !$0 { store.send(.history(.clearDismissed)) } }
        )
    }

    private var toolbar: some View {
        PageHeader(AppSection.history.systemImage, title: AppSection.history.title, subtitle: subtitle) {
            searchField
            actionButton("trash", help: "Clear history") { store.send(.history(.clearTapped)) }
                .disabled(history.history.isEmpty)
        }
        .padding(.bottom, Spacing.extraSmall)
    }

    private var subtitle: String {
        switch history.history.count {
        case 0: "Nothing kept yet."
        case 1: "One transcript, text only."
        case let count: "\(count) transcripts, newest first. Text only."
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
            TextField("Search transcripts", text: searchText)
                .textFieldStyle(.plain)
                .font(Typography.metadata)
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.surfaceSecondary))
        .frame(maxWidth: 220)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(entries) { entry in
                    HistoryRow(
                        transcript: entry,
                        onCopy: { store.send(.history(.copyTapped(entry.id))) },
                        onDelete: { store.send(.history(.deleteTapped(entry.id))) }
                    )
                }
            }
            .padding(.bottom, Spacing.small)
        }
    }

    private func actionButton(
        _ name: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
