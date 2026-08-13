import CoreAudio
import Dependencies
import DependenciesMacros
import Foundation
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "media")

/// Mutes system output for the length of a recording, so a podcast playing through
/// the speakers does not end up in the transcript.
///
/// Mutes the **default output device** rather than sending a play/pause media key.
/// A media key is delivered to whichever app currently owns "now playing", which is
/// frequently the wrong one — and pausing someone's music is a bigger, more visible
/// act than briefly muting it.
@DependencyClient
struct MediaControlClient: Sendable {
    var mute: @Sendable () async -> Void
    /// Restores whatever the volume was before `mute`. A no-op if nothing was muted.
    var unmute: @Sendable () async -> Void
}

extension MediaControlClient: DependencyKey {
    static let liveValue: MediaControlClient = {
        let muter = OutputMuter()
        return MediaControlClient(
            mute: { await muter.mute() },
            unmute: { await muter.unmute() }
        )
    }()
}

extension DependencyValues {
    var mediaControl: MediaControlClient {
        get { self[MediaControlClient.self] }
        set { self[MediaControlClient.self] = newValue }
    }
}

private actor OutputMuter {
    /// The device we muted, so a mid-recording output switch cannot leave some other
    /// device silent forever.
    private var muted: (device: AudioDeviceID, wasMuted: Bool)?

    func mute() {
        guard muted == nil, let device = Self.defaultOutputID() else { return }
        guard let previous = Self.isMuted(device) else {
            log.debug("output device has no mute control; leaving volume alone")
            return
        }
        muted = (device, previous)
        if !previous { Self.setMuted(device, true) }
    }

    func unmute() {
        guard let muted else { return }
        if !muted.wasMuted { Self.setMuted(muted.device, false) }
        self.muted = nil
    }

    private static func defaultOutputID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// nil when the device exposes no mute control — many USB interfaces do not.
    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        return value != 0
    }

    private static func setMuted(_ device: AudioDeviceID, _ muted: Bool) {
        var address = muteAddress()
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        if status != noErr { log.error("could not set mute on \(device) (\(status))") }
    }
}
