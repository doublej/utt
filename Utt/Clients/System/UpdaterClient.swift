import Dependencies
import DependenciesMacros
import Foundation
import Sparkle
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "updater")

/// Sparkle, wrapped so the rest of the app never imports it.
///
/// The updater only starts when `SUFeedURL` is present in the Info.plist. Sparkle
/// aborts with an error when it starts without a feed, and an app that logs a fatal
/// updater error on every launch is worse than one that cannot update — so the guard
/// stays: a build whose feed was stripped hides the update affordances instead of
/// offering a button that fails.
///
/// The feed and the public key are set (see `Info.plist`), so the rest is per
/// release and lives in `just publish`: notarize, upload the zip and the dmg to the
/// GitHub release, then `just appcast` to sign the zip and rewrite `appcast.xml`.
/// `SUEnableAutomaticChecks` is on, so a background check runs on its own; this
/// client only covers the explicit "Check for Updates…" button.
@DependencyClient
struct UpdaterClient: Sendable {
    var isConfigured: @Sendable () -> Bool = { false }
    var checkForUpdates: @Sendable () async -> Void
}

extension UpdaterClient: DependencyKey {
    static let liveValue: UpdaterClient = {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let configured = !(feed ?? "").isEmpty
        guard configured else {
            log.notice("no SUFeedURL — updates disabled")
            return UpdaterClient(isConfigured: { false }, checkForUpdates: {})
        }
        return UpdaterClient(
            isConfigured: { true },
            checkForUpdates: {
                await MainActor.run { Sparkle.shared.checkForUpdates(nil) }
            }
        )
    }()
}

extension DependencyValues {
    var updater: UpdaterClient {
        get { self[UpdaterClient.self] }
        set { self[UpdaterClient.self] = newValue }
    }
}

/// Built on first use rather than at launch. `SPUStandardUpdaterController.init` is
/// main-actor isolated, and constructing it eagerly would make `liveValue` itself
/// main-actor isolated — which `DependencyKey` does not allow.
@MainActor
private enum Sparkle {
    static let shared = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
}
