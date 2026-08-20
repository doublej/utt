import AppKit
import SwiftUI

/// Reaches the `NSWindow` behind a SwiftUI scene for the things SwiftUI has no
/// modifier for: dropping the titlebar's extra height, hiding the traffic lights in
/// the pill, and keeping the pill above other windows.
///
/// A zero-size `NSViewRepresentable` in `.background` is the standard way in, but
/// `window` is nil in `makeNSView` **and** still nil a runloop turn later — the
/// view is attached to its window after that. `viewDidMoveToWindow` is the only
/// hook that reliably fires once there is a window to configure.
struct WindowConfigurator: NSViewRepresentable {
    let collapsed: Bool

    func makeNSView(context: Context) -> NSView {
        WindowHookView(collapsed: collapsed)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? WindowHookView else { return }
        view.collapsed = collapsed
        view.configure()
    }
}

extension NSApplication {
    /// The main scene's window, matched by identifier. In pill mode it is
    /// borderless, and a borderless window answers `false` to `canBecomeMain` —
    /// so any raise path filtering on that matches nothing at all and silently
    /// does nothing. SwiftUI stamps `Window(id: "main")` into the identifier.
    var uttMainWindow: NSWindow? {
        windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }
}

private final class WindowHookView: NSView {
    /// Expanding from the pill restores `.titled`, which makes the window
    /// key-capable again — but nothing makes it key. Raising exactly once per
    /// pill→panel transition keeps typing working without stealing key on
    /// every layout pass.
    var collapsed: Bool {
        didSet {
            guard oldValue != collapsed else { return }
            wantsRaise = !collapsed
        }
    }
    private var wantsRaise = false

    init(collapsed: Bool) {
        self.collapsed = collapsed
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
    }

    func configure() {
        guard let window else { return }
        applyStyle(to: window)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // Only the pill wants a see-through window. Doing this to the expanded panel
        // erases its background *and* its clicks: a non-opaque window hit-tests
        // against rendered alpha, so a transparent panel passes the mouse straight
        // through to whatever is behind it.
        window.backgroundColor = collapsed ? .clear : .windowBackgroundColor
        window.isOpaque = !collapsed
        window.hasShadow = !collapsed
        // Keep the pill above ordinary windows: it is a status readout, and a status
        // readout you have to go looking for is not one.
        window.level = collapsed ? .floating : .normal
        if wantsRaise {
            wantsRaise = false
            // Deferred: configure() runs inside a SwiftUI update pass, and the
            // styleMask change above lands on the window in this same pass.
            DispatchQueue.main.async { window.makeKeyAndOrderFront(nil) }
        }
    }

    /// The pill drops `.titled` entirely. `fullSizeContentView` is not enough — the
    /// titlebar still claims ~32pt *outside* `contentLayoutRect`, so a 48pt capsule
    /// lands in an 80pt window with a transparent band above it, and `setFrame`
    /// cannot win because SwiftUI re-imposes the content height every layout pass.
    ///
    /// The expanded panel keeps `.titled`: those 32pt are where the traffic lights
    /// live, and utty put its header under them the same way.
    private func applyStyle(to window: NSWindow) {
        if collapsed {
            window.styleMask.remove(.titled)
        } else {
            window.styleMask.insert(.titled)
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
