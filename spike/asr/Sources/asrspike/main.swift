import FluidAudio
import Foundation

// Phase 0 spike check #4 — prove FluidAudio 0.15.5's real API surface:
// download + load Parakeet TDT v3, then transcribe one clip. No TCC involved.

/// Not main-actor isolated. `TdtDecoderState` is passed `inout` to an async call,
/// which the compiler rejects for any main-actor-isolated storage — and top-level
/// code in main.swift IS main-actor isolated. So the decoder state has to be a
/// local var inside a nonisolated context like this one, not merely "a local var".
struct Engine {
    func loadAndTranscribe(_ url: URL) async throws -> ASRResult {
        let t0 = Date()
        print("→ downloadAndLoad(version: .v3)  [~461 MB first run, then a ~27s ANE compile]")
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        stamp("models ready", t0)

        let t1 = Date()
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        stamp("manager loaded", t1)

        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)

        let t2 = Date()
        let result = try await asr.transcribe(url, decoderState: &state)
        stamp("transcribed", t2)
        return result
    }

    private func stamp(_ label: String, _ start: Date) {
        print(String(format: "  %@ %.1fs", label, Date().timeIntervalSince(start)))
    }
}

let wav = CommandLine.arguments.dropFirst().first
    ?? "/Users/jurrejan/Documents/development/swift/utt/spike/spike-mic.wav"
let url = URL(fileURLWithPath: wav)
guard FileManager.default.fileExists(atPath: url.path) else {
    print("✗ no audio at \(url.path) — run the permissions spike first")
    exit(1)
}

let result = try await Engine().loadAndTranscribe(url)

print("""

  text:       \(result.text.isEmpty ? "(empty)" : result.text)
  confidence: \(result.confidence)
  duration:   \(result.duration)s
  rtfx:       \(result.rtfx)
""")
print(result.text.isEmpty ? "\n✗ empty transcript" : "\n✓ FluidAudio end to end")
