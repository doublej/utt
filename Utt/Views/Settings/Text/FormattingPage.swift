import ComposableArchitecture
import SwiftUI
import UttCore

/// The last stage: what the text looks like once everything else has had its turn.
struct FormattingPage: View {
    @Shared(.uttSettings) private var settings

    var body: some View {
        SettingsGroup("Formatting") {
            SettingToggle(
                "Lowercase everything",
                detail: "For chat and code, where a capital at the start reads as shouting.",
                isOn: $settings.binding(\.lowercaseTranscripts)
            )
            SettingToggle(
                "Remove punctuation",
                detail: "Every full stop and comma the model added is dropped.",
                isOn: $settings.binding(\.removePunctuation)
            )
        }
    }
}
