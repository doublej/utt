import ComposableArchitecture
import SwiftUI
import UttCore

struct HotkeyPage: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    var body: some View {
        SettingsGroup("Shortcuts") {
            HotkeyRow(store: store)
            SettingRow("Paste the last transcript again", detail: "Wherever the cursor is now.") {
                HotkeyGlyphs(hotkey: AppFeature.pasteLastHotKey)
            }
        }

        SettingsGroup("Holding the key") {
            SettingToggle(
                "Double-tap to lock recording on",
                detail: "Tap twice and recording stays on until the next tap, so a long passage does not need a held key.",
                isOn: $settings.binding(\.doubleTapLockEnabled)
            )
            SettingToggle(
                "Only start on a double-tap",
                detail: "A plain hold is ignored, for a key you also hold for other reasons.",
                isOn: $settings.binding(\.useDoubleTapOnly)
            )
            .disabled(!settings.doubleTapLockEnabled)
            SettingRow(
                "Ignore presses shorter than",
                detail: "A brush against the key should not start a recording."
            ) {
                HStack(spacing: Spacing.extraSmall) {
                    Slider(value: $settings.binding(\.minimumKeyTime), in: 0.05...1.0, step: 0.05)
                        .frame(width: 140)
                    Text(String(format: "%.2fs", settings.minimumKeyTime))
                        .font(Typography.monoSmall)
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

/// Shows the current hotkey and swaps to a live capture field while recording one.
private struct HotkeyRow: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    private var recording: Bool { store.settings.isRecordingHotkey }

    var body: some View {
        SettingRow("Push-to-talk", detail: "Hold to record, let go to paste.") {
            if recording {
                Text("Press the keys…")
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.accent)
            } else {
                HotkeyGlyphs(hotkey: settings.hotkey)
            }
            Button(recording ? "Cancel" : "Change") {
                store.send(.settings(.hotkeyRecordingToggled))
            }
            .font(Typography.metadata)
        }
    }
}
