import AVFoundation
import FluidAudio
import Foundation

// Spike for utt-s2n — prove the ghost-text path of FluidAudio 0.15.5's
// StreamingEouAsrManager: partials arrive on a callback, `process` returns "".
//
// Feeds a wav in chunk-sized slices and prints every partial with two clocks:
// how much audio has been consumed, and how long the wall has taken. The gap
// between them is the lag a person would feel while still holding the key.

struct StreamSpike {
    let chunk: StreamingChunkSize
    let whole: Bool
    let leadIn: Double

    func run(_ url: URL) async throws {
        let t0 = Date()
        let manager = StreamingEouAsrManager(chunkSize: chunk)
        print("→ loadModels(chunkSize: \(chunk.durationMs)ms)  [downloads on first run]")
        try await manager.loadModels(to: nil) { progress in
            print(String(format: "  download %3.0f%%", progress.fractionCompleted * 100))
        }
        stamp("models ready", t0)

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sliceFrames = AVAudioFrameCount(Double(chunk.durationMs) / 1000 * format.sampleRate)
        print("→ feeding \(url.lastPathComponent) in \(chunk.durationMs)ms slices\n")

        // reset() is what allocates the pre-cache and the conformer caches. Without
        // it every chunk decodes to nothing, silently — no error, just no tokens.
        await manager.reset()
        // The cache-aware encoder starts with empty caches; a clip that begins on
        // the first syllable gives it no context to warm on.
        if leadIn > 0 { await manager.injectSilence(leadIn) }

        let start = Date()
        // The callback fires from inside the actor; it only reads the clock and
        // prints, so it stays @Sendable without capturing anything mutable.
        await manager.setPartialCallback { partial in
            print(String(format: "  [wall %5.2fs] %@", Date().timeIntervalSince(start), partial))
        }
        await manager.setEouCallback { text in
            print(String(format: "  [wall %5.2fs] — end of utterance — %@", Date().timeIntervalSince(start), text))
        }

        var audioSeconds = 0.0
        if whole {
            // The CLI's own path: one process() call with the entire file.
            let all = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: all)
            audioSeconds = Double(all.frameLength) / format.sampleRate
            _ = try await manager.process(audioBuffer: all)
        }
        while !whole {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sliceFrames) else { break }
            do {
                try file.read(into: buffer, frameCount: sliceFrames)
            } catch {
                print("✗ read failed at \(String(format: "%.2f", audioSeconds))s: \(error)")
                break
            }
            guard buffer.frameLength > 0 else { break }
            audioSeconds += Double(buffer.frameLength) / format.sampleRate
            do {
                _ = try await manager.process(audioBuffer: buffer)
            } catch {
                print("✗ process failed at \(String(format: "%.2f", audioSeconds))s: \(error)")
                throw error
            }
        }

        let tail: String
        do {
            tail = try await manager.finish()
        } catch {
            print("✗ finish failed: \(error)")
            throw error
        }
        let wall = Date().timeIntervalSince(start)
        print("""

          audio:  \(String(format: "%.2f", audioSeconds))s
          wall:   \(String(format: "%.2f", wall))s  (\(String(format: "%.1f", audioSeconds / wall))x realtime)
          finish: \(tail.isEmpty ? "(empty)" : tail)
        """)
        print(tail.isEmpty ? "\n✗ nothing came back" : "\n✓ streaming end to end")
    }

    private func stamp(_ label: String, _ start: Date) {
        print(String(format: "  %@ %.1fs", label, Date().timeIntervalSince(start)))
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let wav = args.first(where: { !$0.hasPrefix("-") }) ?? "/Users/jurrejan/dev/swift/utt/spike/say-test.wav"
let chunk: StreamingChunkSize =
    args.contains("--320") ? .ms320 : args.contains("--1280") ? .ms1280 : .ms160
let url = URL(fileURLWithPath: wav)
guard FileManager.default.fileExists(atPath: url.path) else {
    print("✗ no audio at \(url.path)")
    exit(1)
}
let leadIn = args.contains("--lead") ? 1.0 : 0.0
try await StreamSpike(chunk: chunk, whole: args.contains("--whole"), leadIn: leadIn).run(url)
