import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// The sign an extension can raise across every screen — see `ExtensionCover`.
///
/// utt draws it and utt polls for it, so a dead extension takes its sign down: no
/// answer is "down". **A sign, not a lock.** One borderless panel per screen that
/// never becomes key or main, never activates utt, and lets every click through —
/// and any input at all takes it down, instantly, because the person at the Mac
/// always outranks whoever is driving it from elsewhere.
@MainActor
final class ExtensionCoverWindows {
    private var panels: [NSPanel] = []
    private var shown: ExtensionCover.Sign?

    /// Just below the Dock (20). Above every app window — normal, floating, modal
    /// panels, the open and save sheet (0–9) — and below every surface the system
    /// draws: the Dock, Notification Centre (21), Siri (23), the menu bar (24), pop-up
    /// menus, the screen saver and the lock screen's shield. Measured with
    /// `CGWindowListCopyWindowInfo` on macOS 26: those are the layers they sit on.
    private static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)

    /// Ephemeral, proxy-free and quick to give up: a loopback address that does not
    /// answer within a second and a half is an extension that is not there.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 1.5
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    init(store: StoreOf<AppFeature>) {
        Task { await watch(store) }
    }

    /// Asks every enabled extension that declared a cover about every two seconds,
    /// and while a sign is up spends those two seconds watching for the person —
    /// four looks a second, which needs no permission at all.
    private func watch(_ store: StoreOf<AppFeature>) async {
        while !Task.isCancelled {
            let addresses = store.settings.extensions
                .filter(\.enabled)
                .compactMap { $0.manifest.cover?.endpoint }
            var asked: ExtensionCover.Sign?
            for address in addresses where asked == nil {
                asked = await Self.ask(address)
            }
            show(ExtensionCover.shown(asked, idle: Self.idle))
            guard shown != nil else {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            for _ in 0 ..< 8 where shown != nil {
                try? await Task.sleep(for: .milliseconds(250))
                show(ExtensionCover.shown(shown, idle: Self.idle))
            }
        }
    }

    private func show(_ sign: ExtensionCover.Sign?) {
        let screens = NSScreen.screens
        let fits = panels.map(\.frame) == screens.map(\.frame)
        guard sign != shown || (sign != nil && !fits) else { return }
        shown = sign
        // Straight off, never faded: someone who touched the Mac is waiting for it.
        panels.forEach { $0.orderOut(nil) }
        panels = sign.map { sign in screens.map { Self.panel(sign, on: $0) } } ?? []
    }

    private static func panel(_ sign: ExtensionCover.Sign, on screen: NSScreen) -> NSPanel {
        let panel = CoverPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = level
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CoverView(sign: sign))
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
        return panel
    }

    /// No redirects: a loopback address must not be able to hand utt on to the network.
    private static func ask(_ address: URL) async -> ExtensionCover.Sign? {
        let request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let (data, response) = try? await session.data(for: request, delegate: NoRedirects()),
              let status = (response as? HTTPURLResponse)?.statusCode, (200 ..< 300).contains(status)
        else { return nil }
        return ExtensionCover.sign(from: data)
    }

    /// Seconds since any key, click or mouse movement in this login session.
    private static var idle: TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}

/// Never key and never main, whatever its style mask becomes: the cover must not take
/// the keystroke that dismisses it, nor the one the daemon is typing into a pane.
private final class CoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

private struct CoverView: View {
    let sign: ExtensionCover.Sign

    var body: some View {
        VStack(spacing: Spacing.large) {
            UttMark(size: 96, hotCore: 0.3)
            Text(sign.title)
                .font(Typography.coverTitle)
            if !sign.detail.isEmpty {
                Text(sign.detail)
                    .font(Typography.coverDetail)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.lcdGround)
        .environment(\.colorScheme, .dark)
    }
}
