import Dependencies
import DependenciesMacros
import Foundation
import UttCore

/// The rewrite lane: an extension that declared `filtersTranscripts` sees each
/// transcript before it lands and may hand back other text.
///
/// The jobs lane in the other direction: utt writes the question into the
/// extension's own directory and waits for the answer beside it. It does not wait
/// long. A filter sits between the key coming up and the text appearing, so a
/// extension that is slow, stopped or wrong costs the person a pause and then
/// nothing — the text passes through as it was.
@DependencyClient
struct ExtensionFiltersClient: Sendable {
    /// The transcript after every filtering extension has had its turn, in id
    /// order. What was heard travels with it: a filter is handed both, and one
    /// that rewrites the text is recorded as a stage that changed it.
    var apply: @Sendable (_ transcript: ProcessedTranscript) async -> ProcessedTranscript = { $0 }
}

extension ExtensionFiltersClient: DependencyKey {
    static let liveValue: ExtensionFiltersClient = {
        let filters = ExtensionFilters()
        return ExtensionFiltersClient(apply: { await filters.apply($0) })
    }()
}

extension DependencyValues {
    var extensionFilters: ExtensionFiltersClient {
        get { self[ExtensionFiltersClient.self] }
        set { self[ExtensionFiltersClient.self] = newValue }
    }
}

/// An actor so two transcripts finishing together — a hotkey and an API call —
/// take their turns, which is what lets `sweep` treat everything already in the
/// directory as stale.
actor ExtensionFilters {
    /// What one extension gets per transcript. Long enough for a local model to
    /// answer, short enough that a dead one reads as a hiccup rather than a hang.
    /// ponytail: one fixed budget; a manifest field if a filter ever needs longer.
    private static let deadline = Duration.seconds(2)
    private static let interval = Duration.milliseconds(50)

    /// Where the questions go. Created for any extension that declared
    /// `filtersTranscripts`, for the same reason the jobs directory is: the extension
    /// has to have somewhere to watch before the first transcript arrives.
    static func directory(_ id: String) -> URL? {
        guard ExtensionManifest.isSafeIdentifier(id),
              let directory = try? URL.uttExtensionsDirectory.appendingPathComponent("\(id).filter")
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Chained in id order: the second extension sees what the first made of it,
    /// and every one of them sees what the recogniser originally heard.
    func apply(_ transcript: ProcessedTranscript) async -> ProcessedTranscript {
        @Dependency(\.continuousClock) var clock
        var output = transcript
        for installed in ExtensionStore.installed().filter({ $0.enabled && $0.manifest.filtersTranscripts }) {
            guard let directory = Self.directory(installed.id) else { continue }
            var replaced = output.text
            // Timed whether or not it rewrote anything: a filter that thought for
            // two seconds and handed the text straight back spent them, and this is
            // the stage most able to.
            let elapsed = await clock.measure {
                replaced = await Self.ask(installed.id, in: directory, transcript: output)
            }
            output = output.applying(.filter, text: replaced, took: elapsed)
        }
        return output
    }

    private static func ask(
        _ id: String, in directory: URL, transcript: ProcessedTranscript
    ) async -> String {
        let text = transcript.text
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
            // Atomic, so the extension never picks up half a question.
            let request = ExtensionFilterRequest(
                text: text,
                raw: transcript.raw,
                stages: transcript.stageNames,
                cleanupSkipped: transcript.cleanupSkipped?.rawValue,
                timings: transcript.timings
            )
            try JSONEncoder().encode(request).writePrivately(to: question)
        } catch {
            ExtensionLog.problem(id, "could not be asked to rewrite a transcript — \(error.localizedDescription)")
            return text
        }
        let clock = ContinuousClock()
        let end = clock.now + deadline
        while clock.now < end {
            if let data = try? Data(contentsOf: answer) {
                guard let replaced = ExtensionFilterReply.text(in: data) else {
                    ExtensionLog.problem(id, "answered a transcript with something utt could not read — the text went through as it was")
                    return text
                }
                return replaced
            }
            try? await Task.sleep(for: interval)
        }
        ExtensionLog.problem(id, "did not answer within \(deadline) — the text went through as it was")
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
