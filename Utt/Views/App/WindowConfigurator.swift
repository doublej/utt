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

private final class WindowHookView: NSView {
    var collapsed: Bool

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
