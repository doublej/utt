import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "plugins")

/// A plugin as utt sees it: what it declared, what the user chose, and whatever it
/// is currently saying about itself.
struct InstalledPlugin: Equatable, Sendable, Identifiable {
    let manifest: PluginManifest
    let values: [String: PluginValue]
    /// From `<id>.status.json` — read-only, the plugin's own words. Empty when the
    /// file is missing, which is what "not running" looks like.
    let status: [String: String]

    var id: String { manifest.id }
    /// The manifest's settings with the stored choices applied.
    var settings: [PluginSetting] { manifest.resolved(stored: values) }
}

/// Plugins talk to utt through files in Application Support, the same way Raycast
/// does. Not through the HTTP API: that needs an enabled listener and a token
/// before anyone can reach it, so a plugin that registered over HTTP would vanish
/// exactly when the API is switched off — while a manifest on disk survives both
/// processes restarting in any order.
@DependencyClient
struct PluginClient: Sendable {
    /// Every manifest in `plugins/`, sanitized, with its values and status.
    var installed: @Sendable () -> [InstalledPlugin] = { [] }
    /// Writes `<id>.values.json`. Atomic, and the revision advances by one.
    var write: @Sendable (_ pluginID: String, _ values: [String: PluginValue], _ api: PluginApiAccess?) -> Void
    /// Hands a finished transcript to every plugin that asked for them.
    var deliver: @Sendable (_ text: String, _ duration: Double, _ app: String?) -> Void
    /// Records that the user pressed one of the plugin's own buttons.
    var request: @Sendable (_ pluginID: String, _ actionKey: String) -> Void
}

extension PluginClient: DependencyKey {
    static let liveValue = PluginClient(
        installed: { PluginStore.installed() },
        write: { id, values, api in PluginStore.write(id, values: values, api: api) },
        deliver: { text, duration, app in PluginStore.deliver(text, duration: duration, app: app) },
        request: { id, key in PluginStore.request(id, action: key) }
    )
}

extension DependencyValues {
    var plugins: PluginClient {
        get { self[PluginClient.self] }
        set { self[PluginClient.self] = newValue }
    }
}

enum PluginStore {
    /// `<id>.values.json` and `<id>.status.json` are also `.json`, so the manifest
    /// scan has to exclude them or a plugin would appear three times.
    private static let reservedSuffixes = [".values.json", ".status.json"]

    static func installed() -> [InstalledPlugin] {
        guard let directory = try? URL.uttPluginsDirectory,
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
    /// say, and writes only when they differ — so a plugin watching the revision
    /// sees it move on a real change and stand still otherwise.
    /// Where a plugin drops audio for transcription. Created for any plugin that
    /// declared `sendsAudio`: it cannot write into a directory that does not exist,
    /// and it has no way to know whether utt has ever seen its manifest.
    static func jobsDirectory(_ id: String) -> URL? {
        guard PluginManifest.isSafeIdentifier(id),
              let directory = try? URL.uttPluginsDirectory.appendingPathComponent("\(id).jobs")
        else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func reconcile(_ plugin: InstalledPlugin, api: PluginApiAccess?) {
        if plugin.manifest.sendsAudio { _ = jobsDirectory(plugin.id) }
        let desired = plugin.settings.reduce(into: [String: PluginValue]()) { $0[$1.key] = $1.value }
        let wanted = plugin.manifest.needsApi ? api : nil
        let current = valuesFile(plugin.id)
        guard desired != current.values || wanted != current.api else { return }
        write(plugin.id, values: desired, api: wanted)
    }

    static func write(_ id: String, values: [String: PluginValue], api: PluginApiAccess?) {
        guard PluginManifest.isSafeIdentifier(id),
              let url = try? URL.uttPluginsDirectory.appendingPathComponent("\(id).values.json")
        else { return }
        let next = valuesFile(id).next(values: values, api: api)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // `.atomic` is write-to-temp-then-rename. A plugin polling this file
            // must never be able to read a half-written one — its failure mode is
            // acting on a setting that was never chosen.
            try encoder.encode(next).write(to: url, options: .atomic)
        } catch {
            log.error("could not write values for \(id, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Asks a plugin to do one of the things it said it could do.
    ///
    /// A request and nothing more: utt writes the key the user pressed and the
    /// plugin decides what that means. Nothing here starts a process.
    static func request(_ id: String, action key: String) {
        guard PluginManifest.isSafeIdentifier(id), PluginManifest.isSafeKey(key),
              let url = try? URL.uttPluginsDirectory.appendingPathComponent("\(id).action.json")
        else { return }
        let previous = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(PluginActionRequest.self, from: $0) }
        let next = PluginActionRequest(
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

    /// Writes the transcript to every plugin that declared `wantsTranscripts`.
    ///
    /// Fire-and-forget and best-effort: a plugin that cannot be written to must not
    /// affect the transcript the person is waiting for. Delivery does not depend on
    /// the history setting — that governs what utt keeps, not what it hands on.
    static func deliver(_ text: String, duration: Double, app: String?) {
        let wanting = installed().filter(\.manifest.wantsTranscripts)
        guard !wanting.isEmpty else { return }
        let finishedAt = ISO8601DateFormatter().string(from: Date())
        for plugin in wanting {
            guard let url = try? URL.uttPluginsDirectory
                .appendingPathComponent("\(plugin.id).transcript.json")
            else { continue }
            let next = PluginTranscript(
                sequence: transcriptFile(plugin.id).sequence &+ 1,
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
                log.error("could not deliver to \(plugin.id, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    /// The sequence is read off disk rather than held in memory, so it survives a
    /// relaunch without a watcher seeing the number go backwards.
    private static func transcriptFile(_ id: String) -> PluginTranscript {
        guard let url = try? URL.uttPluginsDirectory.appendingPathComponent("\(id).transcript.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PluginTranscript.self, from: data)
        else { return PluginTranscript(sequence: 0, text: "", finishedAt: "", duration: 0) }
        return file
    }

    private static func load(_ url: URL) -> InstalledPlugin? {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
        else {
            log.debug("unreadable manifest at \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        // A manifest naming itself something other than its filename would let one
        // plugin write another's values file.
        guard let clean = manifest.sanitized(), clean.id == url.deletingPathExtension().lastPathComponent
        else {
            log.notice("ignoring manifest \(url.lastPathComponent, privacy: .public) — unusable or misnamed")
            return nil
        }
        // A key utt refuses is dropped rather than repaired, and from the plugin's
        // side that is silent: it ships a button and no button appears. Naming it
        // here is the only way its author finds out.
        refused(manifest.actions.map(\.key), kept: clean.actions.map(\.key), of: clean.id, kind: "action")
        refused(manifest.settings.map(\.key), kept: clean.settings.map(\.key), of: clean.id, kind: "setting")
        return InstalledPlugin(
            manifest: clean,
            values: valuesFile(clean.id).values,
            status: status(clean.id)
        )
    }

    /// Manifests are re-read three times a second, so the same refusal would fill
    /// the log forever. Said once per manifest, and again only if the plugin
    /// changes what it declares.
    private static let reported = LockIsolated(Set<String>())

    private static func refused(_ declared: [String], kept: [String], of id: String, kind: String) {
        let missing = declared.filter { !kept.contains($0) }
        guard !missing.isEmpty else { return }
        let keys = missing.joined(separator: ", ")
        guard reported.withValue({ $0.insert("\(id).\(kind): \(keys)").inserted }) else { return }
        log.notice("\(id, privacy: .public): \(kind, privacy: .public) refused — \(keys, privacy: .public)")
    }

    private static func valuesFile(_ id: String) -> PluginValuesFile {
        guard let url = try? URL.uttPluginsDirectory.appendingPathComponent("\(id).values.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PluginValuesFile.self, from: data)
        else { return PluginValuesFile() }
        return file
    }

    /// Strings only, and never interpreted: this is the plugin describing itself,
    /// so utt shows the words it was given rather than deciding what they mean.
    private static func status(_ id: String) -> [String: String] {
        guard let url = try? URL.uttPluginsDirectory.appendingPathComponent("\(id).status.json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return raw.compactMapValues { PluginManifest.text($0, limit: 60) }
    }
}
