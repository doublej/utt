import ComposableArchitecture
import SwiftUI
import UttCore

/// The Text page. The bench first, so every toggle and rule under it rewrites
/// the output the moment it changes, then the rules the bench is showing you.
struct TextPage: View {
    @Shared(.uttSettings) private var settings
    /// The text every rule below is measured against. Owned here because the bench
    /// edits it and the replacement rows read it.
    @State private var sample = RuleBench.cannedSample

    var body: some View {
        RuleBench(sample: $sample)

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

        ReplacementList(sample: sample)
    }
}
