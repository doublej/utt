import ComposableArchitecture
import SwiftUI
import UttCore

struct TextSettings: View {
    @Shared(.uttSettings) private var settings

    var body: some View {
        Card("Delivery") {
            Toggle("Paste at the cursor", isOn: bind(\.useClipboardPaste))
                .help("Off: the transcript is only copied, never pasted")
            Toggle("Leave the transcript on the clipboard", isOn: bind(\.copyToClipboard))
                .help("On: utt does not restore what you had copied before")
        }

        Card("Formatting") {
            Toggle("Lowercase everything", isOn: bind(\.lowercaseTranscripts))
            Toggle("Remove punctuation", isOn: bind(\.removePunctuation))
            Toggle("Remove filler words", isOn: bind(\.wordRemovalsEnabled))
                .help("Deletes uh, um, er, hm")
            if settings.wordRemovalsEnabled {
                Text(settings.wordRemovals.map(\.pattern).joined(separator: "  ·  "))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Palette.textTertiary)
            }
        }

        Card("Replacements") {
            if settings.wordRemappings.isEmpty {
                Text("Nothing replaced. Add a rule for a name or a term the model keeps getting wrong.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
            ForEach(settings.wordRemappings) { rule in
                RemappingRow(rule: rule)
            }
            Button("Add replacement", systemImage: "plus") {
                $settings.withLock {
                    $0.wordRemappings.append(WordRemapping(match: "", replacement: ""))
                }
            }
            .font(Typography.metadata)
        }

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

private struct RemappingRow: View {
    let rule: WordRemapping
    @Shared(.uttSettings) private var settings

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            Toggle("", isOn: field(\.isEnabled))
                .labelsHidden()
            TextField("heard", text: field(\.match))
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
            TextField("written", text: field(\.replacement))
            Button {
                $settings.withLock { $0.wordRemappings.removeAll { $0.id == rule.id } }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove replacement")
        }
        .textFieldStyle(.roundedBorder)
        .font(Typography.metadata)
    }

    /// Edits the rule in place inside the shared array. Looking it up by id each
    /// time means a rule deleted from another view cannot resurrect itself here.
    private func field<Value>(
        _ keyPath: WritableKeyPath<WordRemapping, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                settings.wordRemappings.first { $0.id == rule.id }?[keyPath: keyPath]
                    ?? rule[keyPath: keyPath]
            },
            set: { newValue in
                $settings.withLock { settings in
                    guard let index = settings.wordRemappings.firstIndex(where: { $0.id == rule.id })
                    else { return }
                    settings.wordRemappings[index][keyPath: keyPath] = newValue
                }
            }
        )
    }
}
