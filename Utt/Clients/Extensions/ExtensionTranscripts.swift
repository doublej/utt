//
//  ExtensionTranscripts.swift
//  Utt
//
//  The transcripts lane: every dictation, written to each extension that asked to
//  watch. Its own file beside the jobs and filter lanes, which is where a reader
//  already looks for one of the three.
//

import ComposableArchitecture
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "extensions.transcripts")

extension ExtensionStore {
    /// Writes the transcript to every extension that declared `wantsTranscripts`.
    ///
    /// Fire-and-forget and best-effort: an extension that cannot be written to must not
    /// affect the transcript the person is waiting for. Delivery does not depend on
    /// the history setting — that governs what utt keeps, not what it hands on.
    static func deliver(_ transcript: ProcessedTranscript, duration: Double, app: String?) {
        let wanting = installed().filter { $0.enabled && $0.manifest.wantsTranscripts }
        guard !wanting.isEmpty else { return }
        let finishedAt = ISO8601DateFormatter().string(from: Date())
        for installed in wanting {
            guard let url = try? URL.uttExtensionsDirectory
                .appendingPathComponent("\(installed.id).transcript.json")
            else { continue }
            let next = ExtensionTranscript(
                sequence: transcriptFile(installed.id).sequence &+ 1,
                text: transcript.text,
                // Both versions, always: an extension cannot tell a mishearing from
                // something a stage took out, and it has no other copy to compare
                // against. `stages` is what says which of the two it is.
                raw: transcript.raw,
                stages: transcript.stageNames,
                cleanupSkipped: transcript.cleanupSkipped?.rawValue,
                finishedAt: finishedAt,
                duration: duration,
                timings: transcript.timings,
                app: app
            )
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(next).writePrivately(to: url)
            } catch {
                log.error("could not deliver to \(installed.id, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    /// The sequence is read off disk rather than held in memory, so it survives a
    /// relaunch without a watcher seeing the number go backwards.
    private static func transcriptFile(_ id: String) -> ExtensionTranscript {
        guard let url = try? URL.uttExtensionsDirectory.appendingPathComponent("\(id).transcript.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ExtensionTranscript.self, from: data)
        else { return ExtensionTranscript(sequence: 0, text: "", finishedAt: "", duration: 0) }
        return file
    }
}
