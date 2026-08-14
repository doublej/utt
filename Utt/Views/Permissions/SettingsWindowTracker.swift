import AppKit

/// Reports where the System Settings window is, so a floating card can sit next to
/// it and follow it around.
///
/// Window-server only, deliberately. The accessibility API gives move and resize
/// notifications instead of a poll, but reading them needs Accessibility — which is
/// exactly the permission the user opened this card to grant. `CGWindowList` needs
/// nothing, and 30 Hz keeps up with a window being dragged.
@MainActor
final class SettingsWindowTracker {
    private static let bundleID = "com.apple.systempreferences"
    /// System Settings drops out of the window list for a frame or two while it
    /// swaps panes. One miss is not a closed window; half a second of them is.
    private static let missesBeforeGone = 15
    /// Give up waiting for a window that never arrives rather than polling forever
    /// — the user may have dismissed the system prompt instead.
    private static let pollsBeforeGivingUp = 300

    var onFrame: ((CGRect) -> Void)?
    var onGone: (() -> Void)?

    private var timer: Timer?
    private var frame: CGRect?
    private var misses = 0
    private var pollsBeforeFirstSighting = 0
    private var hasSeenWindow = false

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 1.0 / 120.0
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        frame = nil
        misses = 0
        pollsBeforeFirstSighting = 0
        hasSeenWindow = false
    }

    private func poll() {
        guard let found = settingsWindowFrame() else {
            missed()
            return
        }
        hasSeenWindow = true
        misses = 0
        guard found != frame else { return }
        frame = found
        onFrame?(found)
    }

    private func missed() {
        guard hasSeenWindow else {
            pollsBeforeFirstSighting += 1
            guard pollsBeforeFirstSighting >= Self.pollsBeforeGivingUp else { return }
            stop()
            onGone?()
            return
        }
        misses += 1
        guard misses >= Self.missesBeforeGone else { return }
        stop()
        onGone?()
    }

    /// Several System Settings processes can exist at once; the one with a real
    /// activation policy is the one with the window.
    private func settingsWindowFrame() -> CGRect? {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .first { $0.activationPolicy != .prohibited }
        guard let pid = app?.processIdentifier else { return nil }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        return windows
            .filter { window in
                (window[kCGWindowOwnerPID as String] as? pid_t) == pid
                    && (window[kCGWindowLayer as String] as? Int ?? 0) == 0
                    && (window[kCGWindowAlpha as String] as? Double ?? 1) > 0
            }
            .compactMap { window -> CGRect? in
                guard
                    let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                    let bounds = CGRect(dictionaryRepresentation: dictionary),
                    bounds.width > 320, bounds.height > 240
                else { return nil }
                return Self.appKitFrame(bounds)
            }
            // Settings puts more than one layer-0 surface on screen. The document
            // window is the biggest of them.
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// `CGWindowList` answers in a top-left origin space spanning every display;
    /// AppKit wants bottom-left, relative to the screen the window is actually on.
    private static func appKitFrame(_ rect: CGRect) -> CGRect {
        let screens = NSScreen.screens.compactMap { screen -> (appKit: CGRect, core: CGRect)? in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
            return (screen.frame, CGDisplayBounds(CGDirectDisplayID(number.uint32Value)))
        }
        let overlap = { (screen: CGRect) -> CGFloat in
            let shared = screen.intersection(rect)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        guard let screen = screens.max(by: { overlap($0.core) < overlap($1.core) }),
              overlap(screen.core) > 0
        else { return rect }

        return CGRect(
            x: screen.appKit.minX + rect.minX - screen.core.minX,
            y: screen.appKit.maxY - (rect.minY - screen.core.minY) - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
