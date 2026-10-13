import AVFoundation
import ComposableArchitecture
import Foundation
import UttCore
@testable import utt

/// What `just bench` hands the test host. Absent outside the bench, which is what
/// keeps `just check` from running it.
struct BenchConfig: Sendable {
    let output: URL
    let support: URL
    let runs: Int
    let warmups: Int
    let label: String

    static var current: BenchConfig? {
        let env = ProcessInfo.processInfo.environment
        guard let output = env["UTT_BENCH"], let support = env["UTT_APPLICATION_SUPPORT"] else { return nil }
        return BenchConfig(
            output: URL(filePath: output, directoryHint: .isDirectory),
            support: URL(filePath: support, directoryHint: .isDirectory),
            runs: env["UTT_BENCH_RUNS"].flatMap(Int.init) ?? 20,
            warmups: env["UTT_BENCH_WARMUPS"].flatMap(Int.init) ?? 2,
            label: env["UTT_BENCH_LABEL"] ?? "unlabelled"
        )
    }
}

/// Where in the round trip a moment was taken.
enum BenchPoint: Hashable, Sendable {
    case release, finished, ready, pasted, delivered, located, recorded, saved, handing, handoff, liveFinished
}

/// Moments from every thread the round trip runs on, on one monotonic clock.
final class BenchMarks: Sendable {
    private let times = LockIsolated<[BenchPoint: ContinuousClock.Instant]>([:])
    let transcript = LockIsolated<ProcessedTranscript?>(nil)
    let delivered = LockIsolated<String?>(nil)
    /// Blocks the live recogniser has finished with, for pacing the feed.
    let fed = LockIsolated(0)

    func mark(_ point: BenchPoint) { times.withValue { $0[point] = .now } }

    func reset() {
        times.setValue([:])
        transcript.setValue(nil)
        delivered.setValue(nil)
    }

    func ms(_ start: BenchPoint, _ end: BenchPoint) -> Double? {
        guard let from = times.value[start], let until = times.value[end] else { return nil }
        return from.duration(to: until).inMilliseconds
    }

    /// Runs before `AppFeature`, so the moment is when the store took the action.
    func before(_ action: AppFeature.Action) {
        switch action {
        case .transcription(.recordingFinished): mark(.finished)
        case let .transcription(.transcriptReady(result)):
            mark(.ready)
            transcript.setValue(try? result.get())
        case .transcription(.pasteFinished): mark(.delivered)
        case .history(.record): mark(.recorded)
        default: break
        }
    }

    /// Runs after `AppFeature`: the history reducer has saved by now.
    func after(_ action: AppFeature.Action) {
        if case .history(.record) = action { mark(.saved) }
    }

    func wait(for points: [BenchPoint], timeout: Duration = .seconds(60)) async throws {
        let deadline = ContinuousClock.now + timeout
        while points.contains(where: { times.value[$0] == nil }) {
            guard ContinuousClock.now < deadline else { throw BenchError.timedOut("\(points)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

enum BenchError: Error {
    case timedOut(String)
    case unreadable(String)
    case wrongSupportDirectory(String)
}

extension Duration {
    var inMilliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

/// The microphone, replaced: `stop` keeps the real grace sleep and hands back a
/// copy of the fixture, and `tee` hands the bench the live-words sink.
final class BenchRecorder: Sendable {
    let clip = LockIsolated<RecordingResult?>(nil)
    let sink = LockIsolated<(@Sendable ([Int16]) -> Void)?>(nil)

    /// 1024 frames at 48 kHz, the block a built-in microphone's tap delivers.
    static let grace = StopGrace.period(tapInterval: .seconds(1024.0 / 48_000))

    var client: RecordingClient {
        RecordingClient(
            arm: { _, _, _ in },
            start: { _ in },
            stop: { [clip] in
                try? await Task.sleep(for: Self.grace)
                return clip.value
            },
            cancel: {},
            meterLevel: { 0 },
            reconnect: { _ in },
            tee: { [sink] in sink.setValue($0) }
        )
    }
}

/// A clip `say` wrote, 16 kHz Int16 — the format the capture tap writes.
struct BenchFixture: Sendable {
    let name: String
    let url: URL
    let duration: TimeInterval
    let samples: [Int16]

    init(_ name: String, in directory: URL) throws {
        self.name = name
        url = directory.appending(path: "\(name).wav")
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw BenchError.unreadable(name) }
        try file.read(into: buffer)
        guard let channel = buffer.int16ChannelData?[0] else { throw BenchError.unreadable(name) }
        samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        duration = Double(file.length) / file.fileFormat.sampleRate
    }

    /// A fresh copy per run: the pipeline deletes the clip once it is transcribed.
    func copy(to directory: URL, as name: String = "\(UUID().uuidString).wav") throws -> URL {
        let target = directory.appending(path: name)
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }
}

/// The fastest filter an extension could be: it answers each question with the text
/// it was asked about the moment the file lands, so the filter stage the bench
/// reports is utt's own cost.
final class EchoFilter: @unchecked Sendable {
    let asked = LockIsolated<ExtensionFilterRequest?>(nil)
    private let source: DispatchSourceFileSystemObject

    init(watching directory: URL) {
        let descriptor = open(directory.path, O_EVTONLY)
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: .global(qos: .userInitiated)
        )
        source.setEventHandler { [asked] in Self.answer(in: directory, asked) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }

    private static func answer(in directory: URL, _ asked: LockIsolated<ExtensionFilterRequest?>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".in.json") {
            let answer = directory.appending(path: name.replacingOccurrences(of: ".in.json", with: ".out.json"))
            guard !FileManager.default.fileExists(atPath: answer.path),
                  let data = try? Data(contentsOf: directory.appending(path: name)),
                  let request = try? JSONDecoder().decode(ExtensionFilterRequest.self, from: data)
            else { continue }
            asked.setValue(request)
            try? JSONEncoder().encode(ExtensionFilterReply(text: request.text)).write(to: answer, options: .atomic)
        }
    }
}

/// Everything the round trip reads and writes, laid out in the bench's own
/// Application Support before the store exists.
enum BenchWorld {
    static let filterID = "benchfilter"
    static let watchID = "benchwatch"
    static let jobsID = "benchjobs"

    private struct Manifest: Encodable {
        let id: String
        let name = "Bench"
        var filtersTranscripts = false
        var wantsTranscripts = false
        var sendsAudio = false
        var skipsTextStages: [String] = []
    }

    /// Refuses to go on unless every path utt writes resolves under the bench's own
    /// directory — the check that keeps this away from the real settings and history.
    static func build(_ config: BenchConfig) throws {
        let support = try URL.uttApplicationSupport.resolvingSymlinksInPath().path
        guard support == config.support.resolvingSymlinksInPath().path,
              try URL.uttHistoryFile.path.hasPrefix(URL.uttApplicationSupport.path)
        else { throw BenchError.wrongSupportDirectory(support) }

        let encoder = JSONEncoder()
        try encoder.encode(settings).write(to: URL.uttSettingsFile)
        try encoder.encode(history).write(to: URL.uttHistoryFile)
        let extensions = try URL.uttExtensionsDirectory
        let manifests = [
            Manifest(id: filterID, filtersTranscripts: true),
            Manifest(id: watchID, wantsTranscripts: true),
            // Deckhand's shape: the jobs lane, formatting left to the extension.
            Manifest(id: jobsID, sendsAudio: true, skipsTextStages: ["formatting"])
        ]
        for manifest in manifests {
            try encoder.encode(manifest).write(to: extensions.appending(path: "\(manifest.id).json"))
            ExtensionStore.setEnabled(manifest.id, true)
        }
    }

    /// The profile the round trip is measured on: Parakeet 110M, cleanup and live
    /// words on, immediate ⌘V delivery that puts the clipboard back. The punctuation
    /// preset is what turns a spoken "new paragraph" into a paragraph for cleanup.
    static var settings: UttSettings {
        var settings = UttSettings()
        settings.transcriptionEngine = .parakeet
        settings.selectedModel = "parakeet-tdt-ctc-110m"
        settings.cleanupTranscripts = true
        settings.liveWords = true
        settings.deliveryMode = .immediate
        settings.useClipboardPaste = true
        settings.copyToClipboard = false
        settings.saveTranscriptionHistory = true
        settings.wordRemappings = RulePresets.punctuation
        return settings
    }

    /// A lived-in history: the save rewrites the whole file on every dictation, so
    /// its size is part of the cost. 750 entries of ~110 characters, half
    /// of them with what was heard beside them.
    static var history: TranscriptionHistory {
        let words = String(repeating: "dictated words ", count: 7)
        return TranscriptionHistory(history: (0..<750).map {
            Transcript(
                timestamp: Date(timeIntervalSince1970: Double($0) * 3600),
                text: "\($0) \(words)", raw: $0.isMultiple(of: 2) ? words : nil, duration: 11
            )
        })
    }
}
