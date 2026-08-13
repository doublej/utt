import AVFoundation
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "capture")

func writePreRoll(_ samples: [Int16], to file: AVAudioFile, format: AVAudioFormat) -> Int {
    guard !samples.isEmpty,
          let buffer = AVAudioPCMBuffer(
              pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
          let channel = buffer.int16ChannelData?[0]
    else { return 0 }

    samples.withUnsafeBufferPointer { source in
        guard let base = source.baseAddress else { return }
        channel.update(from: base, count: source.count)
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    do {
        try file.write(from: buffer)
        return samples.count
    } catch {
        log.error("pre-roll write failed: \(error.localizedDescription)")
        return 0
    }
}
