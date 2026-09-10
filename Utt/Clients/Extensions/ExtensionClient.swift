import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "extensions")

/// An extension as utt sees it: what it declared, what the user chose, and whatever it
/// is currently saying about itself.
struct InstalledExtension: Equatable, Sendable, Identifiable {
    let manifest: ExtensionManifest
    let values: [String: ExtensionValue]
    /// From `<id>.status.json` — read-only, the extension's own words. Empty when the
    /// file is missing, which is what "not running" looks like.
    let status: [String: String]
    /// Off is the person's decision, kept in `<id>.disabled` beside the manifest:
    /// the page stays, and nothing the extension declares is acted on.
    var enabled = true

    var id: String { manifest.id }
    /// The manifest's settings with the stored choices applied.
    var settings: [ExtensionSetting] { manifest.resolved(stored: values) }
}

/// Extensions talk to utt through files in Application Support, the same way Raycast
/// does. Not through the HTTP API: that needs an enabled listener and a token
/// before anyone can reach it, so an extension that registered over HTTP would vanish
/// exactly when the API is switched off — while a manifest on disk survives both
/// processes restarting in any order.
@DependencyClient
struct ExtensionClient: Sendable {
    /// Every manifest in `extensions/`, sanitized, with its values and status.
    var installed: @Sendable () -> [InstalledExtension] = { [] }
    /// Writes `<id>.values.json`. Atomic, and the revision advances by one.
    var write: @Sendable (_ extensionID: String, _ values: [String: ExtensionValue], _ api: ExtensionApiAccess?) -> Void
    /// Hands a finished transcript to every extension that asked for them.
    var deliver: @Sendable (_ text: String, _ duration: Double, _ app: String?) -> Void
    /// Records that the user pressed one of the extension's own buttons.
    var request: @Sendable (_ extensionID: String, _ actionKey: String) -> Void
    /// Switches the extension off or on without touching what it wrote.
    var setEnabled: @Sendable (_ extensionID: String, _ enabled: Bool) -> Void
    /// Moves everything utt keeps for the extension to the Trash.
    var remove: @Sendable (_ extensionID: String) -> Void
}

extension ExtensionClient: DependencyKey {
    static let liveValue = ExtensionClient(
        installed: { ExtensionStore.installed() },
        write: { id, values, api in ExtensionStore.write(id, values: values, api: api) },
        deliver: { text, duration, app in ExtensionStore.deliver(text, duration: duration, app: app) },
        request: { id, key in ExtensionStore.request(id, action: key) },
        setEnabled: { id, enabled in ExtensionStore.setEnabled(id, enabled) },
        remove: { id in ExtensionStore.remove(id) }
    )
}

extension DependencyValues {
    var extensions: ExtensionClient {
        get { self[ExtensionClient.self] }
        set { self[ExtensionClient.self] = newValue }
    }
}

enum ExtensionStore {
    /// `<id>.values.json` and `<id>.status.json` are also `.json`, so the manifest
    /// scan has to exclude them or an extension would appear three times.
    private static let reservedSuffixes = [".values.json", ".status.json"]

    static func installed() -> [InstalledExtension] {
        guard let directory = try? URL.uttExtensionsDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }

        return names
            .filter { name in
                name.hasSuffix(".json") && !reservedSuffixes.contains { name.hasSuffix($0) }
            }
            .sorted()
            .compactMap { load(directory.appendingPathComponent($0)) }
    }

    /// Reconciles what is on disk with what the manifest and the API settings now
    /// say, and writes only when they differ — so an extension watching the revision
    /// sees it move on a real change and stand still otherwise.
    /// Where an extension drops audio for transcription. Created for any extension that
    /// declared `sendsAudio`: it cannot write into a directory that does not exist,
    /// and it has no way to know whether utt has ever seen its manifest.
    static func jobsDirectory(_ id: String) -> URL? {
        guard ExtensionManifest.isSafeIdentifier(id),
              let directory = try? URL.uttExtensionsDirectory.appendingPathComponent("\(id).jobs")
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// An empty file, and its presence is the whole state: a marker survives the
    /// extension rewriting its manifest, which it does at every start-up.
    private static func marker(_ id: String) -> URL? {
        try? URL.uttExtensionsDirectory.appendingPathComponent("\(id).disabled")
    }

    static func setEnabled(_ id: String, _ enabled: Bool) {
        guard ExtensionManifest.isSafeIdentifier(id), let marker = marker(id) else { return }
        if enabled {
            try? FileManager.default.removeItem(at: marker)
        } else {
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        }
    }

    /// To the Trash, not deleted: the values file is the person's own choices,
    /// and the extension's status and answers are theirs to look at afterwards.
    static func remove(_ id: String) {
        guard ExtensionManifest.isSafeIdentifier(id),
              let directory = try? URL.uttExtensionsDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for name in names where ExtensionManifest.file(name, belongsTo: id) {
            do {
                try FileManager.default.trashItem(at: directory.appendingPathComponent(name), resultingItemURL: nil)
            } catch {
                log.error("could not remove \(name, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    static func reconcile(_ installed: InstalledExtension, api: ExtensionApiAccess?) {
        if installed.manifest.sendsAudio { _ = jobsDirectory(installed.id) }
        if installed.manifest.filtersTranscripts { _ = ExtensionFilters.directory(installed.id) }
        let desired = installed.settings.reduce(into: [String: ExtensionValue]()) { $0[$1.key] = $1.value }
        let wanted = installed.manifest.needsApi ? api : nil
        let current = valuesFile(installed.id)
        guard desired != current.values || wanted != current.api else { return }
        write(installed.id, values: desired, api: wanted)
    }

    static func write(_ id: String, values: [String: ExtensionValue], api: ExtensionApiAccess?) {
        guard ExtensionManifest.isSafeIdentifier(id),
              let url = try? URL.uttExtensionsDirectory.appendingPathComponent("\(id).values.json")
        else { return }
        let next = valuesFile(id).next(values: values, api: api)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // `.atomic` is write-to-temp-then-rename. An extension polling this file
            // must never be able to read a half-written one — its failure mode is
            // acting on a setting that was never chosen.
            try encoder.encode(next).write(to: url, options: .atomic)
        } catch {
            log.error("could not write values for \(id, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Asks an extension to do one of the things it said it could do.
    ///
    /// A request and nothing more: utt writes the key the user pressed and the
    /// extension decides what that means. Nothing here starts a process.
    static func request(_ id: String, action key: String) {
        guard ExtensionManifest.isSafeIdentifier(id), ExtensionManifest.isSafeKey(key),
              let url = try? URL.uttExtensionsDirectory.appendingPathComponent("\(id).action.json")
        else { return }
        let previous = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(ExtensionActionRequest.self, from: $0) }
        let next = ExtensionActionRequest(
            sequence: (previous?.sequence ?? 0) &+ 1,
            key: key,
            requestedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
        } catch {
            log.error("could not request \(key, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Writes the transcript to every extension that declared `wantsTranscripts`.
    ///
    /// Fire-and-forget and best-effort: an extension that cannot be written to must not
    /// affect the transcript the person is waiting for. Delivery does not depend on
    /// the history setting — that governs what utt keeps, not what it hands on.
    static func deliver(_ text: String, duration: Double, app: String?) {
        let wanting = installed().filter { $0.enabled && $0.manifest.wantsTranscripts }
        guard !wanting.isEmpty else { return }
        let finishedAt = ISO8601DateFormatter().string(from: Date())
        for installed in wanting {
            guard let url = try? URL.uttExtensionsDirectory
                .appendingPathComponent("\(installed.id).transcript.json")
            else { continue }
            let next = ExtensionTranscript(
                sequence: transcriptFile(installed.id).sequence &+ 1,
                text: text,
                finishedAt: finishedAt,
                duration: duration,
                app: app
            )
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(next).write(to: url, options: .atomic)
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

    private static func load(_ url: URL) -> InstalledExtension? {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data)
        else {
            log.debug("unreadable manifest at \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        // A manifest naming itself something other than its filename would let one
        // extension write another's values file.
        guard let clean = manifest.sanitized(), clean.id == url.deletingPathExtension().lastPathComponent
        else {
            log.notice("ignoring manifest \(url.lastPathComponent, privacy: .public) — unusable or misnamed")
            return nil
        }
        // A key utt refuses is dropped rather than repaired, and from the extension's
        // side that is silent: it ships a button and no button appears. Naming it
        // here is the only way its author finds out.
        refused(manifest.actions.map(\.key), kept: clean.actions.map(\.key), of: clean.id, kind: "action")
        refused(manifest.settings.map(\.key), kept: clean.settings.map(\.key), of: clean.id, kind: "setting")
        return InstalledExtension(
            manifest: clean,
            values: valuesFile(clean.id).values,
            status: status(clean.id),
            enabled: marker(clean.id).map { !FileManager.default.fileExists(atPath: $0.path) } ?? true
        )
    }

    /// Manifests are re-read three times a second, so the same refusal would fill
    /// the log forever. Said once per manifest, and again only if the extension
    /// changes what it declares.
    private static let reported = LockIsolated(Set<String>())

    private static func refused(_ declared: [String], kept: [String], of id: String, kind: String) {
        let missing = declared.filter { !kept.contains($0) }
        guard !missing.isEmpty else { return }
        let keys = missing.joined(separator: ", ")
        guard reported.withValue({ $0.insert("\(id).\(kind): \(keys)").inserted }) else { return }
        log.notice("\(id, privacy: .public): \(kind, privacy: .public) refused — \(keys, privacy: .public)")
    }

    private static func valuesFile(_ id: String) -> ExtensionValuesFile {
        guard let url = try? URL.uttExtensionsDirectory.appendingPathComponent("\(id).values.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ExtensionValuesFile.self, from: data)
        else { return ExtensionValuesFile() }
        return file
    }

    /// Strings only, and never interpreted: this is the extension describing itself,
    /// so utt shows the words it was given rather than deciding what they mean.
    private static func status(_ id: String) -> [String: String] {
        guard let url = try? URL.uttExtensionsDirectory.appendingPathComponent("\(id).status.json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return raw.compactMapValues { ExtensionManifest.text($0, limit: 60) }
    }
}
