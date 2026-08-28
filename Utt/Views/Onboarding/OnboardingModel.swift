import ComposableArchitecture
import SwiftUI
import UttCore

/// Screen 3: a 461 MB download is happening, it is the last network access utt
/// needs, and here is where the files it produces will live.
///
/// No model picker. utt has no benchmark across the four, so a list of names would
/// be a choice with nothing to make it on — the screen states the pick and says
/// where the rest are.
struct OnboardingModel: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    /// Resolved, never read raw: a settings file can name a model from an older
    /// build or from the other engine, and what loads is the resolver's answer.
    private var model: TranscriptionModel {
        ModelCatalog.resolve(id: settings.selectedModel, engine: settings.transcriptionEngine)
    }

    var body: some View {
        // `medium` between the cards, not `small`: the card's own inner rhythm is 8,
        // and at 12 the gap between "the model" and "where files live" read as the
        // same gap as the one between a progress bar and its footnote.
        VStack(spacing: Spacing.medium) {
            modelCard
            storageCard
            Spacer(minLength: 0)
        }
        .padding(Spacing.medium)
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            HStack(alignment: .top, spacing: Spacing.extraSmall) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name).font(Typography.primaryRow)
                    Text(model.summary)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: Spacing.small)
                badge
            }
            phase
            Divider().padding(.horizontal, -Spacing.small)
            Text("Picked for you. The rest are in Settings.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(radius: Radius.medium)
    }

    @ViewBuilder private var badge: some View {
        switch store.model {
        case let .downloading(fraction):
            caption("Downloading \(Int(fraction * 100))%", Palette.accent)
        case let .loading(since):
            HStack(spacing: Spacing.xxs) {
                ProgressView().controlSize(.small)
                ElapsedTimer(
                    startedAt: since, font: Typography.monoSmall, tint: Palette.textSecondary
                )
            }
        case .ready:
            Label("Loaded", systemImage: "checkmark.circle.fill")
                .font(Typography.metadata)
                .foregroundStyle(Palette.success)
        case .failed:
            // Not "Download failed": the same state carries a CoreML compile failure,
            // and the message below it already says which one it was.
            caption("Failed", Palette.warning)
        case .idle:
            EmptyView()
        }
    }

    /// Two phases, never one bar. The download knows its own fraction; the CoreML
    /// compile that follows reports nothing and takes a one-time half minute.
    @ViewBuilder private var phase: some View {
        switch store.model {
        case let .downloading(fraction):
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Palette.accent)
            // The one screen where a user is most likely to sit and wait for a bar
            // that nothing is waiting on. Said once, here, and nowhere else.
            Text("Keep going — this finishes in the background.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
        case .loading:
            Text("Getting the model ready for this Mac. One time, about half a minute.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
        case let .failed(message):
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(message)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { store.send(.prepareModelTapped) }
                    .font(Typography.metadata)
            }
        default:
            EmptyView()
        }
    }

    /// The one claim in the whole flow that can be checked rather than believed —
    /// utt is not sandboxed, so this is the real path, openable in Finder.
    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            KickerLabel(text: "Where things live")
            Spacer().frame(height: Spacing.extraSmall)
            Text("~/Library/Application Support/dev.jurrejan.utt")
                .font(Typography.monoSmall)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
            Spacer().frame(height: Spacing.extraSmall)
            Text("""
                The recording is deleted the moment the transcript comes back. \
                Transcripts stay in your history until you clear it.
                """)
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(radius: Radius.medium)
    }

    private func caption(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(Typography.metadata)
            .foregroundStyle(tint)
            .multilineTextAlignment(.trailing)
    }
}
