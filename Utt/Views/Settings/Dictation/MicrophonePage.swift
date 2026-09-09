import ComposableArchitecture
import SwiftUI
import UttCore

struct MicrophonePage: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    var body: some View {
        MicrophonePriority(store: store, devices: store.settings.inputDevices)

        // A Continuity device utt is using through the system default has no row in
        // the priority list, and so nowhere to put its own reconnect button — while
        // being exactly the device that goes silent. It gets one here.
        if !unlistedContinuity.isEmpty {
            SettingsGroup("Continuity") {
                ForEach(unlistedContinuity) { device in
                    SettingRow(
                        device.name,
                        detail: "Not in your priority list, so utt uses it while it is the system input. Reconnect if it has gone quiet."
                    ) {
                        Button("Reconnect") {
                            store.send(.settings(.reconnectMicrophoneTapped(device.id)))
                        }
                        .font(Typography.metadata)
                    }
                }
            }
        }

        SettingsGroup("Capture") {
            SettingToggle(
                "Include audio from just before the keypress",
                detail: "Catches the first word when you start talking before you finish pressing.",
                isOn: $settings.binding(\.preRollEnabled)
            )
            SettingToggle(
                "Keep the microphone warm through sleep and lock",
                detail: "Recording starts instantly after your Mac wakes. The orange microphone dot stays lit while utt runs.",
                isOn: $settings.binding(\.keepMicrophoneWarm)
            )
            SettingToggle(
                "Mute other audio while recording",
                detail: "Whatever is playing pauses, so it does not end up in the transcript.",
                isOn: $settings.binding(\.muteWhileRecording)
            )
            SettingToggle(
                "Keep the Mac awake while recording",
                detail: "A sentence is never cut short by the display going to sleep.",
                isOn: $settings.binding(\.preventSystemSleep)
            )
        }
    }

    /// Attached, reopenable, and not already carrying a button of its own in the
    /// priority list — so no device is offered two ways to do the same thing.
    private var unlistedContinuity: [AudioDevice] {
        store.settings.inputDevices.filter {
            $0.source.canReconnect && !settings.microphonePriority.contains($0.id)
        }
    }
}
