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

        SettingsGroup("Cleanup") {
            SettingToggle(
                "Clean up with Apple Intelligence",
                detail: """
                    Takes out filler words, false starts and mid-sentence corrections, \
                    and puts sentence punctuation back. It runs on this Mac and costs \
                    about a second a paragraph. When the model is unavailable, declines \
                    the text or changes more than a clean-up may, the stage is skipped \
                    and your words are pasted exactly as they were — the panel says why.
                    """,
                isOn: $settings.binding(\.cleanupTranscripts)
            )
        }

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
