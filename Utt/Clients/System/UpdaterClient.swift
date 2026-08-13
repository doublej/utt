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
/// updater error on every launch is worse than one that cannot yet update — so
/// until an appcast is actually hosted, `isConfigured` is false and the UI says so
/// rather than offering a button that fails.
///
/// Shipping checklist, in order:
///   1. `just sparkle-keys` — writes the EdDSA private key to the login keychain
///      and prints the public key. **Back the private key up.** Losing it means
///      every installed copy can no longer be updated, ever.
///   2. Put the printed key in `Info.plist` as `SUPublicEDKey`.
///   3. Host an appcast and put its URL in `Info.plist` as `SUFeedURL`.
///   4. `just appcast` after each release to sign the archive and update the feed.
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
