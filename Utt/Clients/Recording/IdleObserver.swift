import AppKit
import Foundation

/// An armed engine holds the microphone open, which keeps the system's mic-in-use
/// indicator lit for as long as utt is running. That is a fair trade while someone
/// is at the keyboard and a bad one when they are not, so the engine stands down
/// whenever the machine does and comes back when the user does.
///
/// The three signals arrive on two different notification centres, and screen lock
/// is not a `NSWorkspace` notification at all — hence the split.
enum IdleObserver {
    private static let workspaceSuspend: [Notification.Name] = [
        NSWorkspace.willSleepNotification,
        NSWorkspace.screensDidSleepNotification
    ]
    private static let workspaceResume: [Notification.Name] = [
        NSWorkspace.didWakeNotification,
        NSWorkspace.screensDidWakeNotification
    ]

    /// Observers are never removed: this is registered once, for the lifetime of
    /// the process, so the tokens would only ever be dropped on the floor.
    static func observe(
        suspend: @escaping @Sendable () -> Void,
        resume: @escaping @Sendable () -> Void
    ) {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in workspaceSuspend {
            workspace.addObserver(forName: name, object: nil, queue: nil) { _ in suspend() }
        }
        for name in workspaceResume {
            workspace.addObserver(forName: name, object: nil, queue: nil) { _ in resume() }
        }

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: nil
        ) { _ in suspend() }
        distributed.addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: nil
        ) { _ in resume() }
    }
}
