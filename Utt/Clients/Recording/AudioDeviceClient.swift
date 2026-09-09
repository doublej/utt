import AVFoundation
import CoreAudio
import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "devices")

/// An input device, keyed by its UID rather than its `AudioDeviceID`.
///
/// `AudioDeviceID` is a per-boot handle — saving one in settings means the user's
/// chosen microphone silently becomes a different device after a reboot. The UID
/// is stable, which is why `UttSettings.microphonePriority` holds them.
///
/// `source` is what the name alone cannot say: which of these is the phone on the
/// desk, and which is a loopback driver that will never hear a voice.
struct AudioDevice: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let source: DeviceSource
}

@DependencyClient
struct AudioDeviceClient: Sendable {
    var inputDevices: @Sendable () -> [AudioDevice] = { [] }
    /// The device the system would pick, for showing "Default (MacBook Pro Microphone)".
    var defaultInputDevice: @Sendable () -> AudioDevice?
}

extension AudioDeviceClient: DependencyKey {
    static let liveValue = AudioDeviceClient(
        inputDevices: { CoreAudioDevices.inputs() },
        defaultInputDevice: {
            guard let id = CoreAudioDevices.defaultInputID() else { return nil }
            return CoreAudioDevices.describe(id)
        }
    )
}

extension DependencyValues {
    var audioDevices: AudioDeviceClient {
        get { self[AudioDeviceClient.self] }
        set { self[AudioDeviceClient.self] = newValue }
    }
}

/// Thin CoreAudio HAL wrapper. Everything here is synchronous property reads on the
/// HAL, which are cheap and thread-safe.
enum CoreAudioDevices {
    static func inputs() -> [AudioDevice] {
        allDeviceIDs()
            .filter { hasInputStreams($0) }
            .compactMap { describe($0) }
    }

    static func defaultInputID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// Resolves a saved UID back to this boot's handle. Returns nil when the device
    /// is unplugged — the caller then falls back to the system default rather than
    /// recording silence from a device that is not there.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { stringProperty($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    /// What a priority list means *right now*: the best listed device that is
    /// actually plugged in, the system default when none of them is. Callers
    /// compare this, never the list, to decide whether the open device is still the
    /// right one — the answer changes under them as hardware comes and goes, while
    /// the list they asked for stays exactly the same.
    static func resolve(_ uids: [String]) -> AudioDeviceID? {
        uids.lazy.compactMap { deviceID(forUID: $0) }.first ?? defaultInputID()
    }

    static func describe(_ deviceID: AudioDeviceID) -> AudioDevice? {
        guard let uid = stringProperty(deviceID, kAudioDevicePropertyDeviceUID) else { return nil }
        let name = stringProperty(deviceID, kAudioObjectPropertyName) ?? uid
        // Transport is a whole-device fact and lives in the global scope; the data
        // source that tells the internal microphone from the headphone jack is
        // per-scope, and only the input side of it is ours.
        let source = DeviceSource.from(
            transport: codeProperty(deviceID, kAudioDevicePropertyTransportType) ?? "",
            dataSource: codeProperty(
                deviceID, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeInput)
        )
        return AudioDevice(id: uid, name: name, source: source)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    /// Output-only devices answer the same enumeration, so the input scope's stream
    /// configuration is what separates a microphone from a pair of speakers.
    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0
        else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer) == noErr
        else { return false }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    /// A four-character-code property. Transport type and data source both come back
    /// as a packed `UInt32` — `'bltn'`, `'ccwd'` — rather than as a string.
    private static func codeProperty(
        _ deviceID: AudioDeviceID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        // ASCII by definition; a byte outside it is not a code worth guessing at,
        // and `nil` classifies the device as unknown rather than mislabelling it.
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
        return String(bytes: bytes, encoding: .ascii)
    }

    private static func stringProperty(
        _ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // `Unmanaged`, not a bare `CFString`: taking a raw pointer to an ARC-managed
        // reference hands CoreAudio a slot Swift is also writing to. These selectors
        // return a +1 reference, so the value is released on the way out.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, let value else {
            log.debug("property \(selector) unavailable on device \(deviceID)")
            return nil
        }
        return value.takeRetainedValue() as String
    }
}
