import AppKit
import Dependencies
import DependenciesMacros
import Foundation
import ServiceManagement
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "presence")

/// How utt presents itself to the system: whether it starts with the Mac, and
/// whether it appears in the Dock.
///
/// Both are settings the user can flip at any moment, so both have to be applied
/// live — a toggle that only takes effect after a relaunch reads as a broken toggle.
@DependencyClient
struct AppPresenceClient: Sendable {
    var setOpensAtLogin: @Sendable (_ enabled: Bool) async -> Void
    var setShowsDockIcon: @Sendable (_ shown: Bool) async -> Void
}

extension AppPresenceClient: DependencyKey {
    static let liveValue = AppPresenceClient(
        setOpensAtLogin: { enabled in
            let service = SMAppService.mainApp
            // Registering an already-registered service throws, and so does
            // unregistering one that was never there. Comparing first keeps the
            // ordinary no-op path silent.
            let registered = service.status == .enabled
            guard registered != enabled else { return }
            do {
                try enabled ? service.register() : await service.unregister()
                log.notice("login item \(enabled ? "registered" : "unregistered", privacy: .public)")
            } catch {
                // Most often "Operation not permitted" from an unsigned or
                // quarantined copy. Nothing the app can do, and not worth a dialog.
                log.error("login item change failed: \(error.localizedDescription)")
            }
        },
        setShowsDockIcon: { shown in
            await MainActor.run {
                _ = NSApp.setActivationPolicy(shown ? .regular : .accessory)
            }
        }
    )
}

extension DependencyValues {
    var appPresence: AppPresenceClient {
        get { self[AppPresenceClient.self] }
        set { self[AppPresenceClient.self] = newValue }
    }
}
