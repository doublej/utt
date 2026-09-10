import AVFoundation
import CoreAudio
import Foundation

// Plays a wav into one named output device without touching the system default —
// the harness for testing utt's live lane against a known clip through BlackHole.

func deviceID(uid: String) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return nil }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return nil }

    for id in ids {
        var uidRef: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uidRef) == noErr else { continue }
        if uidRef as String? == uid { return id }
    }
    return nil
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2, let device = deviceID(uid: args[1]) else {
    print("usage: playto <file.wav> <output-device-uid>")
    exit(1)
}

let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
try engine.outputNode.auAudioUnit.setDeviceID(device)
let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[0]))
engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
try engine.start()

let done = DispatchSemaphore(value: 0)
player.scheduleFile(file, at: nil) { done.signal() }
player.play()
print("playing \(args[0]) → \(args[1])")
done.wait()
Thread.sleep(forTimeInterval: 0.3)
engine.stop()
