import ComposableArchitecture
import SwiftUI
import UttCore

struct MicrophonePage: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    var body: some View {
        MicrophonePriority(devices: store.settings.inputDevices)

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
}
