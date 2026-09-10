import AVFoundation
import Dependencies
import DependenciesMacros
import FluidAudio
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "live")

/// The words while the key is still down.
///
/// A second recogniser running beside the real one, on its own weights: Parakeet's
/// streaming EOU model decodes 320 ms at a time and hands back everything it has so
/// far. What it produces is **provisional** — it is smaller and less accurate than
/// the model that transcribes the finished clip, and the clip on disk is still what
/// becomes the transcript. Nothing here reaches the cursor.
@DependencyClient
struct LiveTranscriptionClient: Sendable {
    /// Opens a session and returns the transcript as it grows. Each element is the
    /// whole partial, not a delta — the recogniser revises what it already said.
    ///
    /// Returns immediately. The weights load in the background on first use, and a
    /// session opened before they land simply produces nothing.
    var start: @Sendable () async -> AsyncStream<String> = { .finished }
    /// 16 kHz mono samples from the capture tap. Values, never a buffer: the tap
    /// runs on a real-time thread and `AVAudioPCMBuffer` is not `Sendable`.
    var feed: @Sendable (_ samples: [Int16]) async -> Void
    /// Ends the session and frees the decoder state. Idempotent.
    var finish: @Sendable () async -> Void
    /// Whether the streaming weights are on disk. The page that offers the setting
    /// needs to be able to say what turning it on will download.
    var isDownloaded: @Sendable () async -> Bool = { false }
}

extension LiveTranscriptionClient: DependencyKey {
    static let liveValue: LiveTranscriptionClient = {
        let engine = LiveEngine()
        return LiveTranscriptionClient(
            start: { await engine.start() },
            feed: { samples in await engine.feed(samples) },
            finish: { await engine.finish() },
            isDownloaded: { await engine.isDownloaded() }
        )
    }()

    static let testValue = LiveTranscriptionClient()
}

extension DependencyValues {
    var liveTranscription: LiveTranscriptionClient {
        get { self[LiveTranscriptionClient.self] }
        set { self[LiveTranscriptionClient.self] = newValue }
    }
}

private actor LiveEngine {
    /// 320 ms is the vendor's documented default: ~5.7% WER against ~8.3% at 160 ms,
    /// for a delay nobody watching words appear will notice.
    private static let chunk: StreamingChunkSize = .ms320

    private var manager: StreamingEouAsrManager?
    private var loading: Task<StreamingEouAsrManager?, Never>?
    private var session: AsyncStream<String>.Continuation?

    func start() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        session?.finish()
        session = continuation

        Task { [weak self] in
            guard let self, let manager = await self.load() else { return }
            await manager.reset()
            // The callback fires from inside the manager's actor. It only yields a
            // string into the stream, which is the one thing safe to do from there.
            await manager.setPartialCallback { [weak self] partial in
                Task { await self?.yield(partial) }
            }
        }
        return stream
    }

    func feed(_ samples: [Int16]) async {
        guard session != nil, let manager else { return }
        guard let buffer = Self.buffer(from: samples) else { return }
        do {
            _ = try await manager.process(audioBuffer: buffer)
        } catch {
            // A failed chunk costs this recording its ghost text and nothing else:
            // the clip on disk is untouched and the real transcript still happens.
            log.error("live chunk failed: \(error.localizedDescription)")
        }
    }

    func finish() async {
        session?.finish()
        session = nil
        guard let manager else { return }
        _ = try? await manager.finish()
        await manager.reset()
    }

    func isDownloaded() -> Bool {
        FileManager.default.fileExists(atPath: Self.modelDirectory.path)
    }

    private func yield(_ partial: String) {
        session?.yield(partial)
    }

    /// One load, however many recordings ask for it. A second caller arriving mid
    /// download awaits the same task rather than starting a second one.
    private func load() async -> StreamingEouAsrManager? {
        if let manager { return manager }
        if let loading { return await loading.value }

        let task = Task<StreamingEouAsrManager?, Never> {
            let manager = StreamingEouAsrManager(chunkSize: Self.chunk)
            do {
                try await manager.loadModels()
                return manager
            } catch {
                log.error("live weights unavailable: \(error.localizedDescription)")
                return nil
            }
        }
        loading = task
        let loaded = await task.value
        manager = loaded
        loading = nil
        return loaded
    }

    /// `process` wants a buffer, the tap can only hand over values, and this is
    /// where the two meet — on the consumer's side of the isolation boundary.
    private static func buffer(from samples: [Int16]) -> AVAudioPCMBuffer? {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: CaptureController.targetSampleRate,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.int16ChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    private static var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models/parakeet-eou-streaming", isDirectory: true)
    }
}
