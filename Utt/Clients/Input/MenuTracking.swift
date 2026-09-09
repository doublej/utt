import AppKit
import ConcurrencyExtras
import Dependencies
import DependenciesMacros

/// Whether a menu is open right now.
///
/// SwiftUI rebuilds a `MenuBarExtra` — its items *and* its label — whenever the
/// state it reads changes, and a rebuild while the menu is open tears the open menu
/// down. utt's menu is built from what plugins say about themselves, and a plugin
/// that is working rewrites its status file continuously, so the 3 s poll that picks
/// that up was closing the menu roughly as fast as it could be opened.
///
/// `NSMenu` posts both edges of tracking for every menu, submenus included, so the
/// two things that change on a timer can hold still until the menu closes. Kept as
/// a set of the menus tracking rather than a flag: a submenu closing posts an end of
/// its own while the menu that owns it is still open.
final class MenuTracking: Sendable {
    static let shared = MenuTracking()

    private let tracking = LockIsolated(Set<ObjectIdentifier>())

    var isOpen: Bool { !tracking.value.isEmpty }

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [tracking] note in
            guard let menu = note.object as? NSMenu else { return }
            let id = ObjectIdentifier(menu)
            tracking.withValue { _ = $0.insert(id) }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { [tracking] note in
            guard let menu = note.object as? NSMenu else { return }
            let id = ObjectIdentifier(menu)
            tracking.withValue { _ = $0.remove(id) }
        }
    }
}

@DependencyClient
struct MenuTrackingClient: Sendable {
    var isOpen: @Sendable () -> Bool = { false }
}

extension MenuTrackingClient: DependencyKey {
    static let liveValue = MenuTrackingClient { MenuTracking.shared.isOpen }
}

extension DependencyValues {
    var menuTracking: MenuTrackingClient {
        get { self[MenuTrackingClient.self] }
        set { self[MenuTrackingClient.self] = newValue }
    }
}
