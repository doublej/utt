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

        MicrophonePriorityCard(devices: store.settings.inputDevices)

        Card("Capture") {
            Toggle("Include audio from just before the keypress", isOn: bind(\.preRollEnabled))
                .help("Catches the first word when you start talking before you finish pressing")
            Toggle("Keep microphone warm through sleep and lock", isOn: bind(\.keepMicrophoneWarm))
                .help("Recording starts instantly after your Mac wakes. The orange microphone dot stays lit while utt runs.")
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

/// The ordered list of preferred inputs. Capture takes the first one that is
/// plugged in, so this is "AirPods, else the Yeti, else the system default".
///
/// Up/down buttons rather than `List`'s `.onMove`: the settings panel is a
/// `ScrollView`, and a `List` nested in one gets its own scroller and a fixed
/// height it will not give up.
private struct MicrophonePriorityCard: View {
    let devices: [AudioDevice]
    @Shared(.uttSettings) private var settings

    private var priority: [String] { settings.microphonePriority }

    var body: some View {
        Card("Microphone priority") {
            if priority.isEmpty {
                Text("Following the system default input.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            } else {
                ForEach(Array(priority.enumerated()), id: \.element) { index, uid in
                    row(index: index, uid: uid)
                }
            }
            HStack {
                addMenu
                Spacer()
                if !priority.isEmpty {
                    Button("Use system default") { write { $0.removeAll() } }
                        .font(Typography.metadata)
                }
            }
            Text("The first device that is actually plugged in wins. If none of them is, utt falls back to the system default.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func row(index: Int, uid: String) -> some View {
        HStack(spacing: Spacing.small) {
            Text("\(index + 1)")
                .font(Typography.monoSmall)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 14, alignment: .trailing)
            Text(name(of: uid))
                .font(Typography.primaryRow)
                // A device in the list but not on the machine is the whole point of
                // having fallbacks — say so instead of showing a dead row.
                .foregroundStyle(isPresent(uid) ? Palette.textPrimary : Palette.textTertiary)
            if !isPresent(uid) {
                Text("not connected")
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == priority.count - 1)
            Button { write { $0.removeAll { $0 == uid } } } label: { Image(systemName: "minus") }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var addMenu: some View {
        let unlisted = devices.filter { !priority.contains($0.id) }
        Menu("Add microphone") {
            ForEach(unlisted) { device in
                Button(device.name) { write { $0.append(device.id) } }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(unlisted.isEmpty)
    }

    private func isPresent(_ uid: String) -> Bool { devices.contains { $0.id == uid } }

    /// A device that has been unplugged since it was added still has to be nameable.
    /// The remembered name carries it; a bare UID is the last resort, for a device
    /// that has not been seen once since it was listed.
    private func name(of uid: String) -> String {
        devices.first { $0.id == uid }?.name ?? settings.microphoneNames[uid] ?? "Unknown microphone"
    }

    private func move(_ index: Int, by offset: Int) {
        write { $0.swapAt(index, index + offset) }
    }

    private func write(_ change: (inout [String]) -> Void) {
        $settings.withLock { change(&$0.microphonePriority) }
    }
}
