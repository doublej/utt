import ComposableArchitecture
import SwiftUI
import UttCore

/// The Text tab. Delivery first — it is the one setting here that changes what
/// happens to your words rather than how they are spelled — then the bench, then
/// the rules the bench is showing you.
struct TextSettings: View {
    @Shared(.uttSettings) private var settings
    /// The text every rule below is measured against. Owned here because the bench
    /// edits it and the replacement rows read it.
    @State private var sample = RuleBench.cannedSample

    var body: some View {
        DeliveryCard()

        RuleBench(sample: $sample)

        Card("Formatting") {
            Toggle("Lowercase everything", isOn: bind(\.lowercaseTranscripts))
            Toggle("Remove punctuation", isOn: bind(\.removePunctuation))
        }

        ReplacementList(sample: sample)

        Card("History") {
            Toggle("Keep past transcripts", isOn: bind(\.saveTranscriptionHistory))
            Text("Text only — the audio is discarded as soon as it is transcribed.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
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
