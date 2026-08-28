import ComposableArchitecture
import SwiftUI
import UttCore

struct GeneralSettings: View {
    let store: StoreOf<AppFeature>
    @Binding var showingGuide: Bool
    @Binding var showingOnboarding: Bool
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
            HStack {
                Button("Walk me through it") { showingGuide = true }
                if store.needsRelaunch {
                    Button("Restart utt to apply") { store.send(.relaunchTapped) }
                }
            }
            .font(Typography.metadata)
        }

        ModelSettings(store: store)

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
                Button("Show the walkthrough again") { showingOnboarding = true }
                Spacer()
                Button("Reset to defaults", role: .destructive) {
                    store.send(.settings(.resetToDefaultsTapped))
                }
            }
            .font(Typography.metadata)
        }
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
