import ComposableArchitecture
import SwiftUI
import UttCore

/// The second stage: a model pass over what the replacements left. Where the
/// stages that think about the text, rather than match on it, belong.
struct CleanupPage: View {
    @Shared(.uttSettings) private var settings

    var body: some View {
        SettingsGroup {
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
            SettingToggle(
                "Correct grammar",
                detail: """
                    Runs the macOS grammar checker over the text and applies its first \
                    suggestion for each issue. It checks grammar only, not spelling, so \
                    names stay as you said them. Dictation that mixes languages can \
                    confuse it: when it wants to change more than a quarter of the \
                    words, your text is pasted untouched.
                    """,
                isOn: $settings.binding(\.correctGrammar)
            )
        }
    }
}
