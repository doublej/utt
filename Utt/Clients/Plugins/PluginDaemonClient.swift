import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "plugins.daemon")

/// What launchd says about a plugin's daemon.
enum PluginDaemonState: Equatable, Sendable {
    /// Loaded and running, with the pid launchd reports.
    case running(pid: Int)
    /// launchd knows the job but nothing is running — it exited, or crashed.
    case stopped
    /// launchd has never heard of it: not installed, or not loaded into this
    /// session. Distinct from stopped on purpose — "not installed" and "crashed"
    /// call for completely different things from the person reading it.
    case unknown

    var summary: String {
        switch self {
        case let .running(pid): "Running · pid \(pid)"
        case .stopped: "Not running"
        case .unknown: "Not loaded"
        }
    }
}

/// Reports on a plugin's launchd job, and restarts it.
///
/// Deliberately narrow. utt asks launchd about a label and can kick that label;
/// it will not bootstrap, unload, or run anything a manifest names, because a
/// manifest is a file any process on this Mac can write.
@DependencyClient
struct PluginDaemonClient: Sendable {
    var state: @Sendable (_ label: String) async -> PluginDaemonState = { _ in .unknown }
    /// `launchctl kickstart -k` — starts it if it is down, restarts it if it is up.
    /// The one lifecycle verb that needs no plist and cannot leave the job in a
    /// state utt has no way back out of.
    var restart: @Sendable (_ label: String) async -> Void
}

extension PluginDaemonClient: DependencyKey {
    static let liveValue = PluginDaemonClient(
        state: { label in await Launchctl.state(of: label) },
        restart: { label in await Launchctl.restart(label) }
    )
}

extension DependencyValues {
    var pluginDaemon: PluginDaemonClient {
        get { self[PluginDaemonClient.self] }
        set { self[PluginDaemonClient.self] = newValue }
    }
}

private enum Launchctl {
    static func state(of label: String) async -> PluginDaemonState {
        guard PluginDaemon(label: label).isUsable else { return .unknown }
        guard let output = await run(["list", label]) else { return .unknown }
        // `launchctl list <label>` prints a plist-ish dictionary. A job that is
        // loaded but not running has "PID" absent entirely rather than zero.
        guard let line = output.split(separator: "\n").first(where: { $0.contains("\"PID\"") }),
              let pid = Int(line.split(separator: "=").last?
                  .trimmingCharacters(in: CharacterSet(charactersIn: " ;")) ?? "")
        else { return .stopped }
        return .running(pid: pid)
    }

    static func restart(_ label: String) async {
        guard PluginDaemon(label: label).isUsable else { return }
        // The user's own GUI domain, never the system's.
        _ = await run(["kickstart", "-k", "gui/\(getuid())/\(label)"])
    }

    /// nil when launchctl said no — an unknown label exits non-zero.
    private static func run(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                log.error("launchctl \(arguments.first ?? "", privacy: .public) failed: \(error.localizedDescription)")
                return continuation.resume(returning: nil)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(bytes: data, encoding: .utf8)
            continuation.resume(returning: process.terminationStatus == 0 ? output : nil)
        }
    }
}
