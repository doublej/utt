import ComposableArchitecture
import SwiftUI
import UttCore

/// The ordered list of preferred inputs. Capture takes the first one that is
/// plugged in, so this is "AirPods, else the Yeti, else the system default".
///
/// Up/down buttons rather than `List`'s `.onMove`: the settings panel is a
/// `ScrollView`, and a `List` nested in one gets its own scroller and a fixed
/// height it will not give up.
struct MicrophonePriority: View {
    let store: StoreOf<AppFeature>
    let devices: [AudioDevice]
    @Shared(.uttSettings) private var settings

    private var priority: [String] { settings.microphonePriority }

    var body: some View {
        Card("Priority") {
            if priority.isEmpty {
                Text("Following the system default input. Add a microphone to prefer it whenever it is plugged in.")
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
            if let label = source(of: uid)?.label {
                Text(label)
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.textTertiary)
            }
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
            // Only for a device that is actually here — reopening one that is not
            // attached has nothing to open.
            if isPresent(uid), source(of: uid)?.canReconnect == true {
                Button { store.send(.settings(.reconnectMicrophoneTapped(uid))) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reopens this device. A Continuity microphone can stay listed while it has quietly stopped sending audio.")
            }
            Button { write { $0.removeAll { $0 == uid } } } label: { Image(systemName: "minus") }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var addMenu: some View {
        let unlisted = devices.filter { !priority.contains($0.id) }
        Menu("Add microphone") {
            ForEach(unlisted) { device in
                Button(label(for: device)) { write { $0.append(device.id) } }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(unlisted.isEmpty)
    }

    private func label(for device: AudioDevice) -> String {
        device.source.label.map { "\(device.name) · \($0)" } ?? device.name
    }

    private func isPresent(_ uid: String) -> Bool { devices.contains { $0.id == uid } }

    /// How the device is attached, or was the last time it was seen. A device that
    /// has been unplugged keeps its label the way it keeps its name — "USB, and not
    /// here" is a more useful row than a bare name, and it is how you tell two
    /// absent microphones apart.
    private func source(of uid: String) -> DeviceSource? {
        devices.first { $0.id == uid }?.source
            ?? settings.microphoneSources[uid].flatMap(DeviceSource.init(rawValue:))
    }

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
