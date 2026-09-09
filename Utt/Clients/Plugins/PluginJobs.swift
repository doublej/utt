import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "plugins.jobs")

/// The direct lane: a plugin drops an audio file in its own jobs directory and utt
/// writes the text back beside it.
///
/// The same transcription the hotkey and the API use — the engine and model the
/// settings name, then the user's own replacement and formatting rules — reached
/// without a listener, a token, or anything on the network. A plugin on this Mac
/// has no business opening a socket to a program it can already write a file to.
@DependencyClient
struct PluginJobsClient: Sendable {
    /// Starts watching, or restarts with a new transcriber when the engine or
    /// model changes. Idempotent, like `ApiServerClient.apply`.
    var apply: @Sendable (_ transcribe: @escaping PluginJobs.Transcriber) async -> Void
    /// Which plugin's clip is being transcribed right now, and nil between them.
    /// The menu bar lights in that plugin's own colour, so a clip arriving from a
    /// phone is visibly not something typed at this Mac.
    var activity: @Sendable () -> AsyncStream<PluginActivity?> = { .finished }
}

/// A plugin's clip, in flight.
struct PluginActivity: Equatable, Sendable {
    let pluginID: String
    let name: String
    /// The plugin's declared colour, already parsed. Nil falls back to utt's own.
    let rgb: PluginRGB?
}

extension PluginJobsClient: DependencyKey {
    static let liveValue: PluginJobsClient = {
        let runner = PluginJobs()
        return PluginJobsClient(
            apply: { transcribe in await runner.apply(transcribe) },
            activity: { runner.activity() }
        )
    }()
}

extension DependencyValues {
    var pluginJobs: PluginJobsClient {
        get { self[PluginJobsClient.self] }
        set { self[PluginJobsClient.self] = newValue }
    }
}

actor PluginJobs {
    typealias Transcriber = @Sendable (URL) async throws -> String

    /// Short enough that dictation does not feel posted into a queue. Reading one
    /// small directory at this rate costs nothing measurable; a directory watch
    /// would be the upgrade if it ever showed up in a profile.
    private static let interval = Duration.milliseconds(300)
    /// The API's cap, for the same reason: a clip past it is a mistake, and holding
    /// the engine on one blocks every other plugin behind it.
    private static let maximumBytes = ApiConfiguration.maximumBodyBytes

    private var task: Task<Void, Never>?
    private var listeners: [UUID: AsyncStream<PluginActivity?>.Continuation] = [:]

    nonisolated func activity() -> AsyncStream<PluginActivity?> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.add(continuation, id: id) }
            continuation.onTermination = { _ in Task { await self.remove(id) } }
        }
    }

    private func add(_ continuation: AsyncStream<PluginActivity?>.Continuation, id: UUID) {
        listeners[id] = continuation
    }

    private func remove(_ id: UUID) { listeners[id] = nil }

    private func announce(_ activity: PluginActivity?) {
        for listener in listeners.values { listener.yield(activity) }
    }

    func apply(_ transcribe: @escaping Transcriber) {
        task?.cancel()
        task = Task { [weak self] in await self?.watch(transcribe) }
    }

    private func watch(_ transcribe: @escaping Transcriber) async {
        while !Task.isCancelled {
            for (plugin, job) in Self.pending() {
                announce(PluginActivity(
                    pluginID: plugin.id,
                    name: plugin.manifest.name,
                    rgb: plugin.manifest.rgb
                ))
                await run(job, transcribe)
                announce(nil)
            }
            try? await Task.sleep(for: Self.interval)
        }
    }

    /// One job: transcribe, answer beside it, and take the audio away.
    ///
    /// The audio is removed whatever happens. Leaving a clip that failed would mean
    /// retrying it forever at three times a second, and the plugin has the answer
    /// either way.
    private func run(_ audio: URL, _ transcribe: @escaping Transcriber) async {
        defer { try? FileManager.default.removeItem(at: audio) }
        let result: PluginJobResult
        let finishedAt = ISO8601DateFormatter().string(from: Date())
        do {
            let size = (try? audio.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= Self.maximumBytes else {
                let megabytes = Self.maximumBytes / 1024 / 1024
                result = PluginJobResult(
                    error: "That clip is larger than \(megabytes) MB.", finishedAt: finishedAt)
                Self.answer(result, for: audio)
                return
            }
            result = PluginJobResult(text: try await transcribe(audio), finishedAt: finishedAt)
        } catch {
            log.error("job \(audio.lastPathComponent, privacy: .public) failed: \(error.localizedDescription)")
            result = PluginJobResult(error: "Could not transcribe that clip.", finishedAt: finishedAt)
        }
        Self.answer(result, for: audio)
    }

    /// Every audio file waiting in a jobs directory, oldest first so a plugin that
    /// sent two clips gets them back in the order it spoke them.
    private static func pending() -> [(InstalledPlugin, URL)] {
        PluginStore.installed()
            .filter(\.manifest.sendsAudio)
            .flatMap { plugin in files(in: PluginStore.jobsDirectory(plugin.id)).map { (plugin, $0) } }
            .sorted { created($0.1) < created($1.1) }
    }

    private static func files(in directory: URL?) -> [URL] {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        // Only the extensions AVFoundation can open. Anything else — a `.part` file
        // a plugin is still writing, a stray note — is not a job and is left alone.
        return names
            .filter { PluginJobResult.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { directory.appendingPathComponent($0) }
    }

    private static func created(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private static func answer(_ result: PluginJobResult, for audio: URL) {
        let url = audio.deletingPathExtension().appendingPathExtension("json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // Atomic, so a plugin polling for this file never reads a partial one.
            try encoder.encode(result).write(to: url, options: .atomic)
        } catch {
            log.error("could not answer \(audio.lastPathComponent, privacy: .public): \(error.localizedDescription)")
        }
    }
}
