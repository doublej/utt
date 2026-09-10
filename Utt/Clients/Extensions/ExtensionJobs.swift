import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "extensions.jobs")

/// The direct lane: an extension drops an audio file in its own jobs directory and utt
/// writes the text back beside it.
///
/// The same transcription the hotkey and the API use — the engine and model the
/// settings name, then the user's own replacement and formatting rules — reached
/// without a listener, a token, or anything on the network. An extension on this Mac
/// has no business opening a socket to a program it can already write a file to.
@DependencyClient
struct ExtensionJobsClient: Sendable {
    /// Starts watching, or restarts with a new transcriber when the engine or
    /// model changes. Idempotent, like `ApiServerClient.apply`.
    var apply: @Sendable (_ transcribe: @escaping ExtensionJobs.Transcriber) async -> Void
    /// Which extension's clip is being transcribed right now, and nil between them.
    /// The menu bar lights in that extension's own colour, so a clip arriving from a
    /// phone is visibly not something typed at this Mac.
    var activity: @Sendable () -> AsyncStream<ExtensionActivity?> = { .finished }
}

/// An extension's clip, in flight.
struct ExtensionActivity: Equatable, Sendable {
    let extensionID: String
    let name: String
    /// The extension's declared colour, already parsed. Nil falls back to utt's own.
    let rgb: ExtensionRGB?
}

extension ExtensionJobsClient: DependencyKey {
    static let liveValue: ExtensionJobsClient = {
        let runner = ExtensionJobs()
        return ExtensionJobsClient(
            apply: { transcribe in await runner.apply(transcribe) },
            activity: { runner.activity() }
        )
    }()
}

extension DependencyValues {
    var extensionJobs: ExtensionJobsClient {
        get { self[ExtensionJobsClient.self] }
        set { self[ExtensionJobsClient.self] = newValue }
    }
}

actor ExtensionJobs {
    /// The clip, and the pipeline stages the extension that sent it asked to skip.
    /// Passed per job rather than baked into the closure: one transcriber serves
    /// every extension, and they do not agree about the text rules.
    typealias Transcriber = @Sendable (URL, Set<TextStage>) async throws -> ProcessedTranscript

    /// Short enough that dictation does not feel posted into a queue. Reading one
    /// small directory at this rate costs nothing measurable; a directory watch
    /// would be the upgrade if it ever showed up in a profile.
    private static let interval = Duration.milliseconds(300)
    /// The API's cap, for the same reason: a clip past it is a mistake, and holding
    /// the engine on one blocks every other extension behind it.
    private static let maximumBytes = ApiConfiguration.maximumBodyBytes

    private var task: Task<Void, Never>?
    private var listeners: [UUID: AsyncStream<ExtensionActivity?>.Continuation] = [:]

    nonisolated func activity() -> AsyncStream<ExtensionActivity?> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.add(continuation, id: id) }
            continuation.onTermination = { _ in Task { await self.remove(id) } }
        }
    }

    private func add(_ continuation: AsyncStream<ExtensionActivity?>.Continuation, id: UUID) {
        listeners[id] = continuation
    }

    private func remove(_ id: UUID) { listeners[id] = nil }

    private func announce(_ activity: ExtensionActivity?) {
        for listener in listeners.values { listener.yield(activity) }
    }

    func apply(_ transcribe: @escaping Transcriber) {
        task?.cancel()
        task = Task { [weak self] in await self?.watch(transcribe) }
    }

    private func watch(_ transcribe: @escaping Transcriber) async {
        while !Task.isCancelled {
            // One clip per look, not the whole batch. Priority is a question about
            // what goes *next*, and a batch decided before the last transcription
            // started cannot answer it for a clip that arrived since.
            guard let (installed, job) = Self.waiting().first else {
                try? await Task.sleep(for: Self.interval)
                continue
            }
            // Inert, but not silent. An extension the person has not ruled on
            // gets its clip answered with why, rather than watching a file that
            // is never written and having to guess whether utt is broken.
            guard installed.consent == .approved else {
                Self.refuse(job)
                continue
            }
            announce(ExtensionActivity(
                extensionID: installed.id,
                name: installed.manifest.name,
                rgb: installed.manifest.rgb
            ))
            await run(job, installed.manifest.skipsTextStages, transcribe)
            announce(nil)
        }
    }

    /// One job: transcribe, answer beside it, and take the audio away.
    ///
    /// The audio is removed whatever happens. Leaving a clip that failed would mean
    /// retrying it forever at three times a second, and the extension has the answer
    /// either way.
    private func run(
        _ audio: URL, _ skipping: Set<TextStage>, _ transcribe: @escaping Transcriber
    ) async {
        @Dependency(\.date.now) var now
        defer { try? FileManager.default.removeItem(at: audio) }
        let result: ExtensionJobResult
        // Two stamps rather than one: an extension knows when it wrote the clip, but
        // not how much of the wait was this watcher getting to it and how much was the
        // work. One timestamp cannot answer that whichever end it is taken from.
        let started = Self.stamp(now)
        do {
            let size = (try? audio.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= Self.maximumBytes else {
                let megabytes = Self.maximumBytes / 1024 / 1024
                let finished = Self.stamp(now)
                result = ExtensionJobResult(
                    error: "That clip is larger than \(megabytes) MB.",
                    startedAt: started.iso, finishedAt: finished.iso,
                    startedAtMs: started.ms, finishedAtMs: finished.ms)
                Self.answer(result, for: audio)
                return
            }
            let piped = try await transcribe(audio, skipping)
            let final = Self.hinted(piped, for: audio)
            // Stamped here, after the work, which is the whole point of the field.
            result = Self.answered(
                final, seconds: Self.duration(of: audio),
                started: started, finished: Self.stamp(now))
        } catch {
            log.error("job \(audio.lastPathComponent, privacy: .public) failed: \(error.localizedDescription)")
            let finished = Self.stamp(now)
            result = ExtensionJobResult(
                error: "Could not transcribe that clip.",
                startedAt: started.iso, finishedAt: finished.iso,
                startedAtMs: started.ms, finishedAtMs: finished.ms)
        }
        Self.answer(result, for: audio)
    }

    /// The answer for a clip that made it through: the transcript, what each stage
    /// of it cost, and both ends of utt's own stretch.
    private static func answered(
        _ final: ProcessedTranscript, seconds: Double?,
        started: (iso: String, ms: Int), finished: (iso: String, ms: Int)
    ) -> ExtensionJobResult {
        ExtensionJobResult(
            text: final.text, raw: final.raw, stages: final.stageNames,
            cleanupSkipped: final.cleanupSkipped?.rawValue,
            startedAt: started.iso, finishedAt: finished.iso,
            startedAtMs: started.ms, finishedAtMs: finished.ms,
            duration: seconds, timings: final.timings
        )
    }

    /// The transcript with the sender's own hints applied, as their own stage:
    /// named in `stages` rather than folded into `raw` — the answer the API road
    /// already gives. `raw` stays what the recogniser heard.
    private static func hinted(_ piped: ProcessedTranscript, for audio: URL) -> ProcessedTranscript {
        @Dependency(\.continuousClock) var clock
        var corrected = piped.text
        let hinting = clock.measure {
            corrected = TranscriptHints.apply(piped.text, hints: hints(for: audio))
        }
        return piped.applying(.hints, text: corrected, took: hinting)
    }

    /// One moment in both spellings. The ISO string is whole seconds, which is the
    /// shape every extension already parses and cannot be sharpened without
    /// breaking them; the epoch milliseconds are what a span is measured with.
    private static func stamp(_ moment: Date) -> (iso: String, ms: Int) {
        (ISO8601DateFormatter().string(from: moment),
         Int((moment.timeIntervalSince1970 * 1000).rounded()))
    }

    /// Seconds of audio, read off the clip itself. The transcriber hands back text,
    /// and the one road that wants this should not cost every other one a new return
    /// value. Nil for a file the reader cannot open, which is a clip about to fail.
    private static func duration(of audio: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: audio), file.fileFormat.sampleRate > 0
        else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Words the extension knew were coming, from `<name>.hints.json` beside the clip.
    ///
    /// Read at transcription time rather than at pickup, and absent is simply none:
    /// an extension that writes the hints after renaming the audio in has lost the race
    /// it was told about, and gets an uncorrected transcript rather than an error.
    private static func hints(for audio: URL) -> [String] {
        let url = audio.deletingPathExtension().appendingPathExtension("hints.json")
        guard let data = try? Data(contentsOf: url),
              let hints = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        try? FileManager.default.removeItem(at: url)
        return hints
    }

    /// The clip goes, the same as it does on every other outcome: an answered clip
    /// left in place is one utt re-answers three times a second, forever. The
    /// extension resends it once the person has approved it.
    private static func refuse(_ audio: URL) {
        answer(
            ExtensionJobResult(
                error: ExtensionJobResult.awaitingApproval,
                finishedAt: ISO8601DateFormatter().string(from: Date())
            ),
            for: audio
        )
        try? FileManager.default.removeItem(at: audio)
    }

    /// Every audio file waiting in a jobs directory, in the order utt will take
    /// them: the person's band for the extension that sent it, then oldest first —
    /// so an extension that sent two clips still gets them back in the order it
    /// spoke them, whichever band it is in.
    ///
    /// The band decides who goes next and nothing else. A clip already inside the
    /// engine finishes: moving an extension to the front while one is being
    /// transcribed does not interrupt it.
    ///
    /// One the person has switched off is not scanned at all — being off is a thing
    /// they chose and the extension was told about. One they have not ruled on yet is,
    /// so that its clip can be answered with why nothing happened.
    private static func waiting() -> [(InstalledExtension, URL)] {
        ExtensionStore.installed()
            .filter { $0.consent != .disabled && $0.manifest.sendsAudio }
            .flatMap { installed in files(in: ExtensionStore.jobsDirectory(installed.id)).map { (installed, $0) } }
            .sorted { left, right in
                let bands = (left.0.priority.rank, right.0.priority.rank)
                return bands.0 == bands.1 ? created(left.1) < created(right.1) : bands.0 < bands.1
            }
    }

    private static func files(in directory: URL?) -> [URL] {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        // Only the extensions AVFoundation can open. Anything else — a `.part` file
        // an extension is still writing, a stray note — is not a job and is left alone.
        return names
            .filter { ExtensionJobResult.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { directory.appendingPathComponent($0) }
    }

    private static func created(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private static func answer(_ result: ExtensionJobResult, for audio: URL) {
        let url = audio.deletingPathExtension().appendingPathExtension("json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // Atomic, so an extension polling for this file never reads a partial one.
            try encoder.encode(result).writePrivately(to: url)
        } catch {
            log.error("could not answer \(audio.lastPathComponent, privacy: .public): \(error.localizedDescription)")
        }
    }
}
