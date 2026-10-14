import ComposableArchitecture
import SwiftUI
import UttCore

/// The model page: which engine, which model, and — the part a menu could never
/// show — the state of every model at once.
///
/// A `Picker` was the wrong control here. It hides three of the four choices
/// behind a click, and the two facts that decide the choice are per-model: is it
/// already on this disk, and is it the one currently in memory. Rows show both
/// without being opened, at the cost of the height the rows take.
struct ModelPage: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    var body: some View {
        SettingsGroup("Engine") {
            SettingRow(
                "Engine",
                detail: "Parakeet is faster and better on English. Whisper is the fallback for what Parakeet cannot hear."
            ) {
                Picker("Engine", selection: engineBinding) {
                    ForEach(TranscriptionEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }

        SettingsGroup("Models") {
            ForEach(ModelCatalog.models(for: settings.transcriptionEngine)) { model in
                ModelRow(
                    model: model,
                    selected: model.id == selectedModel.id,
                    downloaded: store.downloadedModels.contains(model.id),
                    state: store.model,
                    select: { store.send(.settings(.modelChanged(model.id))) }
                )
            }

            if case .failed = store.model {
                Button("Try again") { store.send(.prepareModelTapped) }
                    .font(Typography.metadata)
            }
        }
    }

    /// Resolved, not read raw — a stored id from an older build or the other engine
    /// has to show as that engine's recommendation, which is what will actually load.
    private var selectedModel: TranscriptionModel {
        ModelCatalog.resolve(id: settings.selectedModel, engine: settings.transcriptionEngine)
    }

    /// Through the reducer rather than straight into settings: changing the engine
    /// has to drop the loaded weights and warm the new ones.
    private var engineBinding: Binding<TranscriptionEngine> {
        Binding(
            get: { settings.transcriptionEngine },
            set: { store.send(.settings(.engineChanged($0))) }
        )
    }
}

/// Four facets side by side, each an icon and a meter of `ModelRatings.scale`
/// dots — the LCD's dot, so the scores read as part of the same instrument.
private struct RatingsStrip: View {
    let ratings: ModelRatings

    var body: some View {
        HStack(spacing: Spacing.small) {
            ForEach(ModelFacet.allCases) { facet in
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: Self.symbol(facet))
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 18)
                    HStack(spacing: 2) {
                        ForEach(1...ModelRatings.scale, id: \.self) { dot in
                            Circle()
                                .fill(dot <= ratings[facet] ? Palette.accent : Palette.strokeStrong)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .help(facet.title)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(facet.title), \(ratings[facet]) of \(ModelRatings.scale)")
            }
        }
    }

    private static func symbol(_ facet: ModelFacet) -> String {
        switch facet {
        case .speed: "hare"
        case .accuracy: "scope"
        case .languages: "globe"
        case .lightness: "leaf"
        }
    }
}

/// One model, and what is true of it right now. Only the selected row can be
/// busy — the engines load one model at a time — so the progress lives here
/// rather than in a status line detached from the thing it describes.
private struct ModelRow: View {
    let model: TranscriptionModel
    let selected: Bool
    let downloaded: Bool
    let state: AppFeature.ModelState
    let select: () -> Void

    var body: some View {
        Button {
            if !selected { select() }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Palette.accent : Palette.textTertiary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.name).font(Typography.primaryRow)
                        Text(model.blurb)
                            .font(Typography.hint)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Spacing.small) {
                            RatingsStrip(ratings: model.ratings)
                                .fixedSize()
                            Text(model.summary)
                                .font(Typography.hint)
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(.top, Spacing.xxs)
                    }
                    Spacer(minLength: Spacing.small)
                    badge
                }
                // Only while this model is the one coming down the wire. Determinate
                // because the engine reports a real fraction; the load that follows
                // does not, and gets the elapsed clock instead.
                if selected, case let .downloading(fraction) = state {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(Palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(selected ? "" : "Switch to \(model.name)")
    }

    @ViewBuilder
    private var badge: some View {
        if selected {
            switch state {
            case let .downloading(fraction):
                caption("Downloading \(Int(fraction * 100))%", Palette.accent)
            case let .loading(since):
                HStack(spacing: Spacing.xxs) {
                    ProgressView().controlSize(.small)
                    // Downloaded is not loaded: picking a model on disk still reads it
                    // into memory, and the first time compiles it for the Neural Engine.
                    caption("Loading", Palette.textSecondary)
                    // No percentage: the loader reports nothing until it returns, so
                    // elapsed time is the only true thing we can show.
                    ElapsedTimer(
                        startedAt: since, font: Typography.monoSmall, tint: Palette.textSecondary
                    )
                }
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.success)
            case let .failed(message):
                caption(message, Palette.warning)
            case .idle:
                caption(downloaded ? "Downloaded" : "Not downloaded", Palette.textTertiary)
            }
        } else {
            caption(downloaded ? "Downloaded" : "Not downloaded", Palette.textTertiary)
        }
    }

    private func caption(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(Typography.metadata)
            .foregroundStyle(tint)
            .multilineTextAlignment(.trailing)
    }
}
