import ComposableArchitecture
import SwiftUI
import UttCore

struct GeneralPage: View {
    let store: StoreOf<AppFeature>
    @Binding var showingOnboarding: Bool
    @Shared(.uttSettings) private var settings

    var body: some View {
        SettingsGroup("Startup") {
            SettingToggle(
                "Open at login",
                detail: "utt starts with your Mac and waits in the menu bar.",
                isOn: $settings.binding(\.openOnLogin)
            )
            SettingToggle(
                "Show in the Dock",
                detail: "Off keeps utt in the menu bar only.",
                isOn: $settings.binding(\.showDockIcon)
            )
        }

        SettingsGroup("Walkthrough") {
            SettingRow(
                "Show the walkthrough again",
                detail: "The first-run tour: permissions, the hotkey, a model, a practice run."
            ) {
                Button("Show") { showingOnboarding = true }
                    .font(Typography.metadata)
            }
        }

        SettingsGroup("Reset") {
            SettingRow(
                "Reset every setting to its default",
                detail: "Everything on these pages goes back to how it shipped. Transcripts are kept."
            ) {
                Button("Reset", role: .destructive) {
                    store.send(.settings(.resetToDefaultsTapped))
                }
                .font(Typography.metadata)
            }
        }
    }
}
