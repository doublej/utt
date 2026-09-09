import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "plugins.filters")

/// The rewrite lane: a plugin that declared `filtersTranscripts` sees each
/// transcript before it lands and may hand back other text.
///
/// The jobs lane in the other direction: utt writes the question into the
/// plugin's own directory and waits for the answer beside it. It does not wait
/// long. A filter sits between the key coming up and the text appearing, so a
/// plugin that is slow, stopped or wrong costs the person a pause and then
/// nothing — the text passes through as it was.
@DependencyClient
struct PluginFiltersClient: Sendable {
    /// The text after every filtering plugin has had its turn, in id order.
    var apply: @Sendable (_ text: String) async -> String = { $0 }
}

extension PluginFiltersClient: DependencyKey {
    static let liveValue: PluginFiltersClient = {
        let filters = PluginFilters()
        return PluginFiltersClient(apply: { await filters.apply($0) })
    }()
}

extension DependencyValues {
    var pluginFilters: PluginFiltersClient {
        get { self[PluginFiltersClient.self] }
        set { self[PluginFiltersClient.self] = newValue }
    }
}

/// An actor so two transcripts finishing together — a hotkey and an API call —
/// take their turns, which is what lets `sweep` treat everything already in the
/// directory as stale.
actor PluginFilters {
    /// What one plugin gets per transcript. Long enough for a local model to
    /// answer, short enough that a dead one reads as a hiccup rather than a hang.
    /// ponytail: one fixed budget; a manifest field if a filter ever needs longer.
    private static let deadline = Duration.seconds(2)
    private static let interval = Duration.milliseconds(50)

    /// Where the questions go. Created for any plugin that declared
    /// `filtersTranscripts`, for the same reason the jobs directory is: the plugin
    /// has to have somewhere to watch before the first transcript arrives.
    static func directory(_ id: String) -> URL? {
        guard PluginManifest.isSafeIdentifier(id),
              let directory = try? URL.uttPluginsDirectory.appendingPathComponent("\(id).filter")
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Chained in id order: the second plugin sees what the first made of it.
    func apply(_ text: String) async -> String {
        var output = text
        for plugin in PluginStore.installed().filter(\.manifest.filtersTranscripts) {
            guard let directory = Self.directory(plugin.id) else { continue }
            output = await Self.ask(plugin.id, in: directory, text: output)
        }
        return output
    }

    private static func ask(_ id: String, in directory: URL, text: String) async -> String {
        sweep(directory)
        let name = UUID().uuidString
        let question = directory.appendingPathComponent("\(name).in.json")
        let answer = directory.appendingPathComponent("\(name).out.json")
        // Both go whatever happens: a question utt stopped waiting for must not be
        // answered into a file nothing reads, at three times a second, forever.
        defer {
            try? FileManager.default.removeItem(at: question)
            try? FileManager.default.removeItem(at: answer)
        }
        do {
            // Atomic, so the plugin never picks up half a question.
            try JSONEncoder().encode(PluginFilterRequest(text: text)).write(to: question, options: .atomic)
        } catch {
            log.error("could not ask \(id, privacy: .public): \(error.localizedDescription)")
            return text
        }
        let clock = ContinuousClock()
        let end = clock.now + deadline
        while clock.now < end {
            if let data = try? Data(contentsOf: answer) {
                guard let replaced = PluginFilterReply.text(in: data) else {
                    log.notice("\(id, privacy: .public): unreadable reply — passed through")
                    return text
                }
                return replaced
            }
            try? await Task.sleep(for: interval)
        }
        log.notice("\(id, privacy: .public): no reply within \(deadline, privacy: .public) — passed through")
        return text
    }

    /// Everything in the directory is a question utt gave up on or an answer
    /// that came too late — only one is ever in flight, and it is cleaned up on
    /// the way out.
    private static func sweep(_ directory: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasSuffix(".in.json") || name.hasSuffix(".out.json") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
