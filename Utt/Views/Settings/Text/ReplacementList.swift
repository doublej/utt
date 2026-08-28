import ComposableArchitecture
import SwiftUI
import UttCore

/// The replacement rules, in the order they run.
///
/// Order is load-bearing — `WordRemappingApplier` applies rules in sequence, so a
/// later one can rewrite an earlier one's output — and until this list could be
/// dragged, the UI had no way to say so.
struct ReplacementList: View {
    /// The bench text each row's hit dot is measured against.
    let sample: String

    @Shared(.uttSettings) private var settings

    private static let rowHeight: CGFloat = 30

    var body: some View {
        Card("Replacements") {
            if settings.wordRemappings.isEmpty {
                Text("Nothing replaced. Add a rule for a name or a term the model keeps getting wrong.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            } else {
                rules
            }
            HStack(spacing: Spacing.small) {
                Button("Add replacement", systemImage: "plus") {
                    $settings.withLock {
                        $0.wordRemappings.append(WordRemapping(match: "", replacement: ""))
                    }
                }
                Button("Spoken punctuation") { seed(RulePresets.punctuation) }
                    .help("Adds the rules you do not already have, to edit from there")
                Spacer()
            }
            .font(Typography.metadata)

            Text("Leave the right side empty to delete the word.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func seed(_ preset: [WordRemapping]) {
        $settings.withLock { RulePresets.appendMissing(preset, to: &$0.wordRemappings) }
    }

    /// A `List` purely for `.onMove`: it is the only container that gives rows a
    /// drag handle for free. Its own scrolling is off — the settings panel already
    /// scrolls, and two scroll views inside each other is a trap.
    private var rules: some View {
        List {
            ForEach(settings.wordRemappings) { rule in
                RemappingRow(rule: rule, sample: sample)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                $settings.withLock {
                    $0.wordRemappings.move(fromOffsets: source, toOffset: destination)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: CGFloat(settings.wordRemappings.count) * Self.rowHeight)
    }
}

private struct RemappingRow: View {
    let rule: WordRemapping
    let sample: String

    @Shared(.uttSettings) private var settings

    /// Filled when this rule fires against the bench sample. The answer to "why is
    /// my rule not doing anything", without dictating anything to find out.
    private var hits: Bool {
        WordRemappingApplier.matches(rule, in: sample)
    }

    /// Nothing on the right-hand side: this rule takes the word out.
    private var deletes: Bool {
        !rule.match.trimmingCharacters(in: .whitespaces).isEmpty && rule.replacement.isEmpty
    }

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(systemName: hits ? "circle.fill" : "circle")
                .font(.system(size: 6))
                .foregroundStyle(hits ? Palette.accent : Palette.textTertiary)
                .help(hits ? "Matches the text above" : "No match in the text above")
            Toggle("", isOn: field(\.isEnabled))
                .labelsHidden()
            TextField("what you say", text: field(\.match))
            Image(systemName: deletes ? "arrow.right.to.line.compact" : "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
                .help(deletes ? "Deletes the word" : "Replaces the word")
            TextField("what utt types", text: field(\.replacement))
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
