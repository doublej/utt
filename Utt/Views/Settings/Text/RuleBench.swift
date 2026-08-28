import ComposableArchitecture
import SwiftUI
import UttCore

/// Sample in, transcript out — the whole pipeline, live.
///
/// This is what turns the Text tab from a page of checkboxes into a tool: every
/// toggle above and every rule below rewrites the output the moment it changes,
/// so "Remove punctuation" stops being a guess about what it might do.
struct RuleBench: View {
    @Binding var sample: String

    @Shared(.uttSettings) private var settings
    @Shared(.uttHistory) private var transcripts

    /// Exercises the parts people actually configure: a word to delete, spoken
    /// punctuation, and a proper noun a model routinely lowercases.
    static let cannedSample = "um so I told claude code new line ship it comma please"

    var body: some View {
        Card("Try it out") {
            TextEditor(text: $sample)
                .font(Typography.mono)
                .scrollContentBackground(.hidden)
                .frame(height: 54)
                .padding(Spacing.xxs)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .strokeBorder(Palette.strokeHairline, lineWidth: 0.5)
                )

            HStack(spacing: Spacing.small) {
                Button("Use last transcript") {
                    if let text = transcripts.history.first?.text { sample = text }
                }
                .disabled(transcripts.history.isEmpty)
                Button("Reset") { sample = Self.cannedSample }
                Spacer()
            }
            .font(Typography.metadata)

            Divider()

            Text(output.isEmpty ? "Every word here is deleted by a rule." : output)
                .font(Typography.mono)
                .foregroundStyle(output.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var output: String {
        settings.applyTextTransforms(to: sample)
    }
}
