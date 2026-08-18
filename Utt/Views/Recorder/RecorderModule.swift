import ComposableArchitecture
import SwiftUI
import UttCore

/// The always-visible strip above the content: which mic, which engine, and either
/// the running clock or a reminder of the hotkey.
struct RecorderModule: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    private var recording: Bool { store.transcription.isRecording }

    var body: some View {
        VStack(spacing: Spacing.extraSmall) {
            topRow
            VuMeter(level: store.transcription.meterLevel, active: recording)
        }
        .padding(.vertical, Spacing.small)
        .padding(.horizontal, Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
        .overlay(border)
        .animation(.smooth(duration: 0.25), value: recording)
    }

    private var topRow: some View {
        HStack(spacing: Spacing.small) {
            HStack(spacing: 6) {
                KickerLabel(text: "MIC")
                MicrophonePicker(
                    devices: store.settings.inputDevices,
                    defaultName: store.settings.defaultInputName
                )
            }
            Spacer(minLength: Spacing.extraSmall)
            HStack(spacing: 6) {
                KickerLabel(text: "MODEL")
                EnginePicker(store: store)
            }
            timerOrHotkey
        }
    }

    @ViewBuilder
    private var timerOrHotkey: some View {
        if recording {
            ElapsedTimer(startedAt: store.transcription.recordingStartedAt)
        } else {
            HStack(spacing: 6) {
                // Says what the hotkey actually does, because in double-tap-only
                // mode holding it does nothing at all.
                KickerLabel(text: settings.useDoubleTapOnly ? "TAP TAP" : "HOLD")
                HotkeyGlyphs(hotkey: settings.hotkey)
            }
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            .strokeBorder(
                recording ? Palette.recording.opacity(0.55) : Palette.strokeHairline,
                lineWidth: recording ? 1.0 : 0.5
            )
    }
}

private struct MicrophonePicker: View {
    let devices: [AudioDevice]
    let defaultName: String?
    @Shared(.uttSettings) private var settings

    var body: some View {
        Picker("Microphone", selection: binding) {
            Text(defaultLabel).tag(String?.none)
            ForEach(devices) { device in
                Text(device.name).tag(String?.some(device.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 170)
    }

    private var defaultLabel: String {
        defaultName.map { "System default (\($0))" } ?? "System default"
    }

    /// Settings live in `@Shared`, not in feature state, so this writes through the
    /// lock rather than through a `BindingAction`.
    ///
    /// Picking a device promotes it to the head of the priority list rather than
    /// replacing the list — the fallbacks the user set up in Settings survive a
    /// quick switch. "System default" is the empty list.
    private var binding: Binding<String?> {
        Binding(
            get: { settings.microphonePriority.first },
            set: { newValue in
                $settings.withLock { settings in
                    guard let newValue else { return settings.microphonePriority = [] }
                    settings.microphonePriority = [newValue]
                        + settings.microphonePriority.filter { $0 != newValue }
                }
            }
        )
    }
}

private struct EnginePicker: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    var body: some View {
        Picker("Engine", selection: binding) {
            ForEach(TranscriptionEngine.allCases, id: \.self) { engine in
                Text(engine.displayName).tag(engine)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 150)
    }

    /// Switching engines is not a plain write — the old weights have to come out of
    /// memory first — so this routes through the reducer.
    private var binding: Binding<TranscriptionEngine> {
        Binding(
            get: { settings.transcriptionEngine },
            set: { store.send(.settings(.engineChanged($0))) }
        )
    }
}
