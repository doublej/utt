import AppKit
import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "permissions")

enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    /// Never asked. Only in this state can `request` produce a prompt.
    case notDetermined
}

enum Permission: String, CaseIterable, Sendable {
    /// Reading the global hotkey — CGPreflight/RequestListenEventAccess.
    case inputMonitoring
    /// Synthesizing ⌘V — CGPreflight/RequestPostEventAccess. Shown under Accessibility.
    case accessibility
    case microphone

    var settingsAnchor: String {
        switch self {
        case .inputMonitoring: "Privacy_ListenEvent"
        case .accessibility: "Privacy_Accessibility"
        case .microphone: "Privacy_Microphone"
        }
    }

    var title: String {
        switch self {
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        case .microphone: "Microphone"
        }
    }

    var rationale: String {
        switch self {
        case .inputMonitoring: "so utt can see your push-to-talk hotkey"
        case .accessibility: "so utt can paste the transcript at your cursor"
        case .microphone: "so utt can hear you"
        }
    }
}

/// macOS permission handling has two traps that shape this whole API:
///
/// 1. **The system prompts once per app per service, ever.** After the first
///    request there is no second dialog — the only route is System Settings. So
///    `request` reports whether it could even prompt, and callers must be ready to
///    deep-link instead.
/// 2. **A granted permission never reaches a process that already asked.** The
///    grant only takes effect on relaunch. `needsRelaunch` detects that state so
///    the UI can offer a restart rather than appearing to hang.
@DependencyClient
struct PermissionClient: Sendable {
    var status: @Sendable (_ permission: Permission) -> PermissionStatus = { _ in .notDetermined }
    /// Returns true if a system prompt was actually presented.
    var request: @Sendable (_ permission: Permission) async -> Bool = { _ in false }
    var openSettings: @Sendable (_ permission: Permission) -> Void
    /// True when TCC says granted but this process still sees a denial.
    var needsRelaunch: @Sendable () -> Bool = { false }
    var relaunch: @Sendable () -> Void
}

extension PermissionClient: DependencyKey {
    /// `status` is not reliable on its first call: `CGPreflight*` kicks off an
    /// asynchronous TCC lookup and answers "denied" until it lands, so an already
    /// granted permission reports missing for the first few milliseconds of a
    /// launch. Burning a warm-up call here does not help — the lookup is still in
    /// flight. `AppFeature` handles it by requiring two consecutive observations.
    static let liveValue: PermissionClient = {
        PermissionClient(
            status: { permission in
                switch permission {
                case .inputMonitoring:
                    CGPreflightListenEventAccess() ? .granted : .denied
                case .accessibility:
                    CGPreflightPostEventAccess() ? .granted : .denied
                case .microphone:
                    switch AVCaptureDevice.authorizationStatus(for: .audio) {
                    case .authorized: .granted
                    case .notDetermined: .notDetermined
                    default: .denied
                    }
                }
            },
            request: { permission in
                switch permission {
                case .inputMonitoring:
                    return CGRequestListenEventAccess()
                case .accessibility:
                    return CGRequestPostEventAccess()
                case .microphone:
                    // Do NOT block the calling thread waiting on this. A semaphore
                    // wait on the main thread starves the run loop that TCC needs to
                    // present its prompt: the dialog never renders and the callback
                    // never fires.
                    return await AVCaptureDevice.requestAccess(for: .audio)
                }
            },
            openSettings: { permission in
                let anchor = permission.settingsAnchor
                let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
                guard let url else { return }
                NSWorkspace.shared.open(url)
            },
            needsRelaunch: { RelaunchDetector.shared.isStale() },
            relaunch: {
                let url = Bundle.main.bundleURL
                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                    Task { @MainActor in NSApp.terminate(nil) }
                }
            }
        )
    }()
}

extension DependencyValues {
    var permissions: PermissionClient {
        get { self[PermissionClient.self] }
        set { self[PermissionClient.self] = newValue }
    }
}

/// Remembers what the preflight said at launch. If the user grants a permission
/// while the app is running, the in-process answer stays stale until relaunch —
/// but `CGRequest*` starts returning true, so the two disagree. That disagreement
/// is the signal.
private final class RelaunchDetector: @unchecked Sendable {
    static let shared = RelaunchDetector()

    private let listenAtLaunch: Bool
    private let postAtLaunch: Bool

    init() {
        listenAtLaunch = CGPreflightListenEventAccess()
        postAtLaunch = CGPreflightPostEventAccess()
    }

    func isStale() -> Bool {
        (!listenAtLaunch && CGPreflightListenEventAccess())
            || (!postAtLaunch && CGPreflightPostEventAccess())
    }
}
