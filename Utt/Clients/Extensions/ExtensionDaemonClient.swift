import Dependencies
import DependenciesMacros
import Foundation
import UttCore

/// What launchd says about an extension's daemon.
enum ExtensionDaemonState: Equatable, Sendable {
    /// Loaded and running, with the pid launchd reports.
    case running(pid: Int)
    /// launchd knows the job and nothing is running, and the last run ended
    /// cleanly. Switched off, in other words.
    case stopped
    /// launchd knows the job, nothing is running, and the last run ended badly.
    ///
    /// Its own case because "Restart starts it" is the wrong thing to tell someone
    /// whose daemon is crash-looping on a permanent error — a port already taken,
    /// a missing file — and Restart is the button they will press twenty times. A
    /// looping job also *has* a pid for about a second in every ten, so which state
    /// a poll catches is luck; the exit status is the half that holds still.
    case failing(status: Int)
    /// launchd has never heard of it: not installed, or not loaded into this
    /// session. Distinct from stopped on purpose — "not installed" and "crashed"
    /// call for completely different things from the person reading it.
    case unknown

    var summary: String {
        switch self {
        case let .running(pid): "Running · pid \(pid)"
        case .stopped: "Not running"
        case let .failing(status): "Crashed · \(Self.ending(status))"
        case .unknown: "Not loaded"
        }
    }

    /// launchd reports what `wait` reports: the exit code in the high byte, and the
    /// signal that killed it in the low one. 36608 is a process that exited 143,
    /// not one that was signalled.
    private static func ending(_ status: Int) -> String {
        let signal = status & 0x7F
        return signal == 0 ? "exit \(status >> 8)" : "signal \(signal)"
    }
}

/// Reports on an extension's launchd job, and restarts it.
///
/// Deliberately narrow. utt asks launchd about a label and can kick that label;
/// it will not bootstrap, unload, or run anything a manifest names, because a
/// manifest is a file any process on this Mac can write.
@DependencyClient
struct ExtensionDaemonClient: Sendable {
    var state: @Sendable (_ label: String) async -> ExtensionDaemonState = { _ in .unknown }
    /// `launchctl kickstart -k` — starts it if it is down, restarts it if it is up.
    /// The one lifecycle verb that needs no plist and cannot leave the job in a
    /// state utt has no way back out of.
    var restart: @Sendable (_ label: String) async -> Void
}

extension ExtensionDaemonClient: DependencyKey {
    static let liveValue = ExtensionDaemonClient(
        state: { label in await Launchctl.state(of: label) },
        restart: { label in await Launchctl.restart(label) }
    )
}

extension DependencyValues {
    var extensionDaemon: ExtensionDaemonClient {
        get { self[ExtensionDaemonClient.self] }
        set { self[ExtensionDaemonClient.self] = newValue }
    }
}

private enum Launchctl {
    static func state(of label: String) async -> ExtensionDaemonState {
        guard ExtensionDaemon(label: label).isUsable else { return .unknown }
        guard let output = await run(["list", label]) else { return .unknown }
        // `launchctl list <label>` prints a plist-ish dictionary. A job that is
        // loaded but not running has "PID" absent entirely rather than zero.
        let report = ExtensionDaemon.report(fromList: output)
        if let pid = report.pid { return .running(pid: pid) }
        // Absent or zero is a job that was asked to stop, which is not a crash.
        guard let status = report.lastExitStatus, status != 0 else { return .stopped }
        return .failing(status: status)
    }

    static func restart(_ label: String) async {
        guard ExtensionDaemon(label: label).isUsable else { return }
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
                ExtensionLog.problem(nil, "could not run launchctl \(arguments.first ?? "") — \(error.localizedDescription)")
                return continuation.resume(returning: nil)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(bytes: data, encoding: .utf8)
            continuation.resume(returning: process.terminationStatus == 0 ? output : nil)
        }
    }
}
