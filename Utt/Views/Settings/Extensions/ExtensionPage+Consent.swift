import ComposableArchitecture
import SwiftUI
import UttCore

/// The two halves of the decision: what the extension asked for, and the answer.
///
/// Every line here is the extension's own claim about itself. utt renders a
/// manifest; it cannot open the program behind it, and there is no signature and
/// no registry to check one against — so the page says what was *asked for*, never
/// what the extension does. Wording that promised more than utt can see would be
/// the consent step lying on the extension's behalf.
extension ExtensionPage {
    /// Shown instead of the working page while nobody has ruled on it. The whole
    /// page is the question, so the answer is at the top of it.
    @ViewBuilder
    var pendingConsent: some View {
        Card("Waiting for you") {
            Text("Something on this Mac put \(installed.manifest.name) in utt's extensions folder. It is not running inside utt and utt did not download it — but until you approve it, utt hands it nothing: no audio, no transcripts, no token, and nothing you change on this page is saved for it.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("What is below is what \(installed.manifest.name) says about itself. utt cannot check any of it. Approve it because you know what put it there.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.small) {
                Button("Approve") {
                    store.send(.settings(.extensionEnabledChanged(installed.id, true)))
                }
                .keyboardShortcut(.defaultAction)
                Button("Remove…") { removing = true }
                Spacer(minLength: 0)
            }
            .font(Typography.metadata)
        }
    }

    /// What the manifest asked utt for, in the extension's own account of itself.
    /// The same list before and after approving: it is the reason to say yes, and
    /// the reason to change your mind later.
    @ViewBuilder
    var access: some View {
        if installed.manifest.wantsTranscripts || installed.manifest.needsApi
            || installed.manifest.sendsAudio || installed.manifest.filtersTranscripts
            || installed.manifest.wantsPartials || installed.manifest.wantsWordTimings {
            SettingsGroup("What it asked for") {
                if installed.manifest.filtersTranscripts {
                    SettingRow(
                        "To rewrite your transcripts",
                        detail: "Sees each transcript before it is pasted and can hand back different text. If it does not answer within two seconds, the text goes through as you said it."
                    ) {
                        Image(systemName: "wand.and.sparkles").foregroundStyle(Palette.textTertiary)
                    }
                }
                if installed.manifest.sendsAudio {
                    SettingRow(
                        "To send audio to be transcribed",
                        detail: "Drops clips in a folder of its own and gets the text back. Transcribed on this Mac, with your engine and your text rules. Nothing goes over the network."
                    ) {
                        Image(systemName: "waveform").foregroundStyle(Palette.textTertiary)
                    }
                }
                if !installed.manifest.skipsTextStages.isEmpty {
                    SettingRow("To skip some of your text rules", detail: skipNote) {
                        Image(systemName: "text.badge.minus").foregroundStyle(Palette.textTertiary)
                    }
                }
                if installed.manifest.wantsWordTimings {
                    SettingRow(
                        "To know where each word was spoken",
                        detail: "Gets the second each word starts and ends, for the clips it sends itself. Nothing about what you dictate."
                    ) {
                        Image(systemName: "waveform.badge.magnifyingglass").foregroundStyle(Palette.textTertiary)
                    }
                }
                if installed.manifest.wantsTranscripts {
                    SettingRow(
                        "To receive your transcripts",
                        detail: "Everything you dictate on this Mac is written to this extension's own file as it finishes, whether or not utt keeps it in History."
                    ) {
                        Image(systemName: "text.quote").foregroundStyle(Palette.textTertiary)
                    }
                }
                if installed.manifest.wantsPartials {
                    SettingRow(
                        "To hear you as you speak",
                        detail: "Gets the words while you are still talking, before any of your text rules run. Only while Show words while you speak is on."
                    ) {
                        Image(systemName: "waveform.badge.mic").foregroundStyle(Palette.textTertiary)
                    }
                }
                if installed.manifest.needsApi {
                    SettingRow("For the API token", detail: apiNote, detailTint: apiTint) {
                        Image(systemName: "network").foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
    }
}
