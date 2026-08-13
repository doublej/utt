import ComposableArchitecture
import SwiftUI
import UttCore

struct RecordingSettings: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    var body: some View {
        Card("Hotkey") {
            HotkeyRow(store: store)
            Divider()
            Toggle("Double-tap to lock recording on", isOn: bind(\.doubleTapLockEnabled))
            Toggle("Only start on double-tap", isOn: bind(\.useDoubleTapOnly))
                .disabled(!settings.doubleTapLockEnabled)
                .help("Ignores a plain hold, for a hotkey you also hold for other reasons")
            minimumHold
        }

        Card("Capture") {
            Toggle("Include audio from just before the keypress", isOn: bind(\.preRollEnabled))
                .help("Keeps a rolling buffer so the first syllable is not clipped")
            Toggle("Keep microphone warm through sleep and lock", isOn: bind(\.keepMicrophoneWarm))
                .help("Prevents the engine from suspending on idle — keeps the mic-in-use indicator lit")
            Toggle("Mute other audio while recording", isOn: bind(\.muteWhileRecording))
            Toggle("Keep the Mac awake while recording", isOn: bind(\.preventSystemSleep))
        }
    }

    private var minimumHold: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Ignore presses shorter than")
                    .font(Typography.primaryRow)
                Spacer()
                Text(String(format: "%.2fs", settings.minimumKeyTime))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
            Slider(value: bind(\.minimumKeyTime), in: 0.05...1.0, step: 0.05)
            Text("A brush against the key should not start a recording.")
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

/// Shows the current hotkey and swaps to a live capture field while recording one.
private struct HotkeyRow: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    var body: some View {
        HStack {
            Text("Push-to-talk")
                .font(Typography.primaryRow)
            Spacer()
            if store.settings.isRecordingHotkey {
                Text("Press the keys…")
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.accent)
            } else {
                HotkeyGlyphs(hotkey: settings.hotkey)
            }
            Button(store.settings.isRecordingHotkey ? "Cancel" : "Change") {
                store.send(.settings(.hotkeyRecordingToggled))
            }
            .font(Typography.metadata)
        }
    }
}
