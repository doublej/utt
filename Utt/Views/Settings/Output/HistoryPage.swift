import ComposableArchitecture
import SwiftUI
import UttCore

struct HistoryPage: View {
    @Shared(.uttSettings) private var settings
    @Shared(.uttHistory) private var transcripts

    /// The offered caps, plus whatever the file already says: a hand-edited value
    /// has to show as selected rather than as an empty menu.
    private var caps: [Int] {
        Array(Set([100, 500, 2000] + [settings.maxHistoryEntries].compactMap { $0 })).sorted()
    }

    var body: some View {
        SettingsGroup {
            SettingToggle(
                "Keep past transcripts",
                detail: "Text only. The audio is discarded as soon as it is transcribed.",
                isOn: $settings.binding(\.saveTranscriptionHistory)
            )
            SettingRow("Keep at most", detail: "The oldest transcripts are dropped once the list is this long.") {
                Picker("Keep at most", selection: $settings.binding(\.maxHistoryEntries)) {
                    Text("Everything").tag(Int?.none)
                    ForEach(caps, id: \.self) { cap in
                        Text("\(cap)").tag(Int?.some(cap))
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            .disabled(!settings.saveTranscriptionHistory)
            SettingRow("Stored now", detail: "Search and re-paste them from the main window.") {
                Text("\(transcripts.history.count)")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
        }
    }
}
