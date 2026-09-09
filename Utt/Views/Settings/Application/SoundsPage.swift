import ComposableArchitecture
import SwiftUI
import UttCore

struct SoundsPage: View {
    @Shared(.uttSettings) private var settings

    var body: some View {
        SettingsGroup("Sounds") {
            SettingToggle(
                "Play a sound on start and stop",
                detail: "A short chime either side of a recording.",
                isOn: $settings.binding(\.soundEffectsEnabled)
            )
            SettingRow("Volume") {
                HStack(spacing: Spacing.extraSmall) {
                    Image(systemName: "speaker.wave.1")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                    Slider(value: $settings.binding(\.soundEffectsVolume), in: 0...1)
                        .frame(width: 140)
                        .tint(Palette.accent)
                }
            }
            .disabled(!settings.soundEffectsEnabled)
        }

        SettingsGroup("Indicator") {
            SettingToggle(
                "Show the indicator in the middle of the screen",
                detail: "The dot-matrix mark that appears while you talk. The menu bar icon still moves.",
                isOn: $settings.binding(\.showRecordingOverlay)
            )
        }
    }
}
