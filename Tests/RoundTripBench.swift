import AppKit
import ComposableArchitecture
import Foundation
import Testing
import UttCore
@testable import utt

/// `just bench`: the real pipeline from "recording stopped" to the extension
/// hand-off, timed through the real reducers. Live Parakeet, cleanup, the filter,
/// transcripts and jobs lanes and the history save; the microphone is the only
/// stage replaced, and the paste lands on a private pasteboard with no ⌘V posted.
/// Skipped unless `just bench` set it up.
@MainActor
@Suite("Round trip bench", .enabled(if: BenchConfig.current != nil))
struct RoundTripBench {
    @Test("release to text, to pasteFinished, to transcript.json, and the jobs lane")
    func measure() async throws {
        let config = try #require(BenchConfig.current)
        try BenchWorld.build(config)
        let safety = try await withDependencies {
            $0.defaultFileStorage = .fileSystem
        } operation: {
            try await BenchSession(config).run()
        }
        #expect(safety["eventTapsInThisProcess"] == "0")
        #expect(safety["listeningSockets"] == "none")
    }
}

@MainActor
final class BenchSession {
    static let hotkeys = ["hotkey-3s", "hotkey-11s", "hotkey-30s"]
    static let jobs = "jobs-11s"
    static let clipboard = "the clipboard before the paste"
    static let boardName = NSPasteboard.Name("dev.jurrejan.utt.bench")
    /// 1024 frames at 48 kHz, resampled to 16 kHz: what one tap block hands the sink.
    static let block = 341

    let config: BenchConfig
    let marks: BenchMarks
    let recorder = BenchRecorder()
    let fixtures: [String: BenchFixture]
    let filter: EchoFilter
    let scratch: URL
    let board = NSPasteboard(name: boardName)
    let store: StoreOf<AppFeature>
    @Shared(.uttHistory) var history

    init(_ config: BenchConfig) throws {
        self.config = config
        let marks = BenchMarks()
        self.marks = marks
        scratch = config.support.appending(path: "scratch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let directory = config.output.appending(path: "fixtures")
        fixtures = try Dictionary(uniqueKeysWithValues: Self.hotkeys.map { ($0, try BenchFixture($0, in: directory)) })
        guard let questions = ExtensionFilters.directory(BenchWorld.filterID)
        else { throw BenchError.unreadable(BenchWorld.filterID) }
        filter = EchoFilter(watching: questions)
        store = Self.makeStore(marks, recorder)
    }

    func run() async throws -> [String: String] {
        let load = try await loadModel()
        // What a launch does with settings: arms the jobs lane with the transcriber.
        store.send(.settings(.dictationChanged(true)))
        let cold = try await roundTrip(fixture("hotkey-11s")).0
        var samples: [String: [[String: Double]]] = ["cold": [cold]]
        var outputs: [String: [BenchOutput]] = [:]
        // Round robin rather than one scenario at a time, so a drift in thermal state
        // or background load lands on every scenario alike.
        for round in 0..<(config.warmups + config.runs) {
            for name in Self.hotkeys + [Self.jobs] {
                let (stages, output) = name == Self.jobs
                    ? try await job(fixture("hotkey-11s"))
                    : try await roundTrip(fixture(name))
                if round >= config.warmups {
                    samples[name, default: []].append(stages)
                    outputs[name, default: []].append(output)
                }
                // Past the history save's one-second coalescing window, so every
                // dictation pays the immediate write a real one does.
                try await Task.sleep(for: .seconds(1))
            }
        }
        let safety = BenchReport.safety()
        let result = BenchResult(
            label: config.label, date: Date(), runs: config.runs, warmups: config.warmups,
            modelLoadMs: load, fixtureSeconds: fixtures.mapValues(\.duration), safety: safety,
            scenarios: samples.mapValues(BenchReport.summarize)
        )
        try BenchReport.write(result, outputs: outputs, to: config.output)
        return safety
    }

    private func fixture(_ name: String) throws -> BenchFixture {
        guard let fixture = fixtures[name] else { throw BenchError.unreadable(name) }
        return fixture
    }

    /// The weights, loaded the way a launch loads them: the next decode is the cold one.
    private func loadModel() async throws -> Double {
        let model = BenchWorld.settings.selectedModel
        let start = ContinuousClock.now
        for await _ in TranscriptionClient.liveValue.prepare(.parakeet, model) {}
        guard await TranscriptionClient.liveValue.isReady(.parakeet, model) else { throw BenchError.unreadable(model) }
        return start.duration(to: .now).inMilliseconds
    }

    /// One dictation: key down, the clip streamed to the live recogniser, key up,
    /// and everything after it until the extension has its transcript.
    private func roundTrip(_ fixture: BenchFixture) async throws -> ([String: Double], BenchOutput) {
        marks.reset()
        filter.asked.setValue(nil)
        board.clearContents()
        board.setString(Self.clipboard, forType: .string)
        let clip = try fixture.copy(to: scratch)
        recorder.clip.setValue(RecordingResult(url: clip, duration: fixture.duration, peak: 0.5))
        store.send(.transcription(.hotKey(.startRecording)))
        let pressed = ContinuousClock.now
        try await feed(fixture.samples)
        // Held for the clip's length up to three seconds, so what the press started —
        // the cleanup prewarm, the live recogniser's first chunks — has had the time
        // a person speaking gives it. Longer clips stream faster than they were spoken.
        try await Task.sleep(until: pressed + .seconds(min(fixture.duration, 3)), clock: .continuous)
        marks.mark(.release)
        store.send(.transcription(.hotKey(.stopRecording)))
        try await marks.wait(for: [.handoff, .liveFinished])
        return (stages(), try output())
    }

    /// Tap-sized blocks into the live-words sink while the key is down: as fast as
    /// the streaming recogniser takes them, but never so far ahead that its 64-block
    /// buffer drops audio the real tap would have delivered. Release then finds it
    /// where it is in a real dictation — caught up, with under 320 ms left over.
    private func feed(_ samples: [Int16]) async throws {
        var sink = recorder.sink.value
        while sink == nil {
            try await Task.sleep(for: .milliseconds(5))
            sink = recorder.sink.value
        }
        marks.fed.setValue(0)
        let blocks = stride(from: 0, to: samples.count, by: Self.block).map {
            Array(samples[$0..<min($0 + Self.block, samples.count)])
        }
        for (index, block) in blocks.enumerated() {
            sink?(block)
            while index + 1 - marks.fed.value >= 32 { try await Task.sleep(for: .milliseconds(1)) }
        }
        while marks.fed.value < blocks.count { try await Task.sleep(for: .milliseconds(2)) }
    }

    private func stages() -> [String: Double] {
        let timings = marks.transcript.value?.timings ?? [:]
        let spans: [String: Double?] = [
            "a.text": marks.ms(.release, .pasted),
            "b.pasteFinished": marks.ms(.release, .delivered),
            "c.handoff": marks.ms(.release, .handoff),
            "stop": marks.ms(.release, .finished),
            "transcribe": marks.ms(.finished, .ready),
            "decode": timings["decode"],
            "rules": (timings["replacements"] ?? 0) + (timings["formatting"] ?? 0),
            "cleanup": timings["cleanup"],
            "filter": timings["filter"],
            "paste": marks.ms(.ready, .pasted),
            "restore": marks.ms(.pasted, .delivered),
            "frontmost": marks.ms(.delivered, .recorded),
            "history": marks.ms(.recorded, .saved),
            "transcriptJson": marks.ms(.saved, .handoff),
            "liveFinish": marks.ms(.release, .liveFinished)
        ]
        return spans.compactMapValues { $0 }
    }

    /// Everything a dictation produced that an optimization must leave alone.
    private func output() throws -> BenchOutput {
        let file = try URL.uttExtensionsDirectory.appending(path: "\(BenchWorld.watchID).transcript.json")
        return BenchOutput(
            delivered: marks.delivered.value,
            transcript: marks.transcript.value.flatMap { BenchOutput.stripped($0, dropping: ["timings"]) },
            filterInput: filter.asked.value.flatMap { BenchOutput.stripped($0, dropping: ["timings"]) },
            extensionFile: (try? Data(contentsOf: file)).flatMap {
                BenchOutput.stripped($0, dropping: ["timings", "finishedAt", "sequence", "app"])
            },
            history: history.history.first.map { "\($0.text)\n--- raw ---\n\($0.raw ?? "")" },
            clipboardRestored: board.string(forType: .string) == Self.clipboard
        )
    }

    /// Deckhand's lane: a clip renamed into the jobs directory, timed until the
    /// answer beside it exists.
    private func job(_ fixture: BenchFixture) async throws -> ([String: Double], BenchOutput) {
        guard let jobs = ExtensionStore.jobsDirectory(BenchWorld.jobsID) else { throw BenchError.unreadable(BenchWorld.jobsID) }
        let name = "bench-\(UUID().uuidString)"
        let staged = try fixture.copy(to: scratch, as: "\(name).wav")
        let answer = jobs.appending(path: "\(name).json")
        filter.asked.setValue(nil)
        let sent = Date().timeIntervalSince1970 * 1000
        let start = ContinuousClock.now
        try FileManager.default.moveItem(at: staged, to: jobs.appending(path: "\(name).wav"))
        try await Self.waitForFile(answer)
        let total = start.duration(to: .now).inMilliseconds
        let arrived = Date().timeIntervalSince1970 * 1000
        let data = try Data(contentsOf: answer)
        try FileManager.default.removeItem(at: answer)
        let result = try JSONDecoder().decode(ExtensionJobResult.self, from: data)
        let spans: [String: Double?] = [
            "total": total,
            "pickup": result.startedAtMs.map { Double($0) - sent },
            "work": result.finishedAtMs.flatMap { end in result.startedAtMs.map { Double(end - $0) } },
            "decode": result.timings?["decode"],
            "cleanup": result.timings?["cleanup"],
            "filter": result.timings?["filter"],
            "answer": result.finishedAtMs.map { arrived - Double($0) }
        ]
        let dropped: Set = ["timings", "startedAt", "finishedAt", "startedAtMs", "finishedAtMs"]
        return (spans.compactMapValues { $0 }, BenchOutput(
            filterInput: filter.asked.value.flatMap { BenchOutput.stripped($0, dropping: ["timings"]) },
            jobAnswer: BenchOutput.stripped(data, dropping: dropped)
        ))
    }

    /// Off the main actor, so a millisecond poll does not compete with the reducer.
    nonisolated private static func waitForFile(_ url: URL, timeout: Duration = .seconds(60)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !FileManager.default.fileExists(atPath: url.path) {
            guard ContinuousClock.now < deadline else { throw BenchError.timedOut(url.lastPathComponent) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
