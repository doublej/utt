import ComposableArchitecture
import SwiftUI
import UttCore

struct GeneralSettings: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    var body: some View {
        Card("Permissions") {
            ForEach(Permission.allCases, id: \.self) { permission in
                PermissionRow(
                    permission: permission,
                    granted: !store.missingPermissions.contains(permission),
                    action: { store.send(.grantTapped(permission)) }
                )
            }
            if store.needsRelaunch {
                Button("Restart utt to apply") { store.send(.relaunchTapped) }
                    .font(Typography.metadata)
            }
        }

        Card("Model") {
            Picker("Engine", selection: engineBinding) {
                ForEach(TranscriptionEngine.allCases, id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            Picker("Model", selection: modelBinding) {
                ForEach(ModelCatalog.models(for: settings.transcriptionEngine)) { model in
                    Text(model.name).tag(model.id)
                }
            }
            HStack {
                Text(selectedModel.summary)
                    .font(Typography.metadata)
                    .foregroundStyle(.secondary)
                Spacer()
                ModelStatusLabel(state: store.model)
            }
            if case .failed = store.model {
                Button("Try again") { store.send(.prepareModelTapped) }
                    .font(Typography.metadata)
            }
        }

        Card("Sounds") {
            Toggle("Play a sound on start and stop", isOn: bind(\.soundEffectsEnabled))
            if settings.soundEffectsEnabled {
                Slider(value: bind(\.soundEffectsVolume), in: 0...1)
            }
        }

        Card("App") {
            Toggle("Show in the Dock", isOn: bind(\.showDockIcon))
            Toggle("Open at login", isOn: bind(\.openOnLogin))
            HStack {
                Spacer()
                Button("Reset to defaults", role: .destructive) {
                    store.send(.settings(.resetToDefaultsTapped))
                }
            }
            .font(Typography.metadata)
        }
    }

    /// Resolved, not read raw — a stored id from an older build or the other engine
    /// has to show as that engine's recommendation, which is what will actually load.
    private var selectedModel: TranscriptionModel {
        ModelCatalog.resolve(id: settings.selectedModel, engine: settings.transcriptionEngine)
    }

    /// Both go through the reducer rather than writing settings directly: changing
    /// either one has to drop the loaded weights and warm the new ones.
    private var engineBinding: Binding<TranscriptionEngine> {
        Binding(
            get: { settings.transcriptionEngine },
            set: { store.send(.settings(.engineChanged($0))) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { selectedModel.id },
            set: { store.send(.settings(.modelChanged($0))) }
        )
    }

    private func bind<Value>(
        _ keyPath: WritableKeyPath<UttSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in $settings.withLock { $0[keyPath: keyPath] = newValue } }
        )
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Palette.success : Palette.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(permission.title).font(Typography.primaryRow)
                Text(permission.rationale)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            if !granted {
                Button("Allow", action: action).font(Typography.metadata)
            }
        }
    }
}

private struct ModelStatusLabel: View {
    let state: AppFeature.ModelState

    var body: some View {
        switch state {
        case .idle, .preparing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                // No percentage: the loader reports nothing until it returns, so
                // elapsed time is the only true thing we can show.
                if case let .preparing(since) = state {
                    ElapsedTimer(startedAt: since, font: Typography.monoSmall, tint: Palette.textSecondary)
                }
            }
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(Typography.metadata)
                .foregroundStyle(Palette.success)
        case let .failed(message):
            Text(message)
                .font(Typography.metadata)
                .foregroundStyle(Palette.warning)
        }
    }
}
