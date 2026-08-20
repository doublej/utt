import AppKit
import SwiftUI

/// A floating card that follows the System Settings window and carries utt's own
/// bundle as a draggable file.
///
/// The privacy panes are Finder drop targets: dropping an `.app` on the list adds
/// the row. macOS normally adds it for us the moment utt calls the API, so this is
/// the recovery path for when it did not — a stale row left by an older copy, or a
/// grant orphaned by a certificate change. The row always lands switched **off**,
/// so the drag never replaces flipping the toggle.
@MainActor
final class DragToSettingsPanel {
    static let shared = DragToSettingsPanel()

    private static let gap: CGFloat = 12

    private let tracker = SettingsWindowTracker()
    private var panel: NSPanel?

    private init() {
        tracker.onFrame = { [weak self] frame in self?.snap(beside: frame) }
        tracker.onGone = { [weak self] in self?.hide() }
    }

    /// Nothing appears until the tracker has actually found the window: System
    /// Settings may still be launching, and may never open at all when macOS
    /// answered with its own prompt instead.
    func show(for permission: Permission) {
        guard permission.supportsDropTarget else { return }
        hide()
        panel = makePanel(for: permission)
        tracker.start()
    }

    func hide() {
        tracker.stop()
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(for permission: Permission) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: cardSize),
            // Non-activating, so starting the drag does not pull utt in front of the
            // window the user is about to drop onto.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(
            rootView: DragCard(permission: permission) { [weak panel] dragging in
                // The panel sits above everything; left clickable it would swallow
                // the drop it exists to deliver.
                panel?.ignoresMouseEvents = dragging
            }
        )
        return panel
    }

    private func snap(beside settings: CGRect) {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? settings
        let size = cardSize

        // Beside the list, not under the window: the drop target is the app list in
        // the content pane, so the shortest drag is a sideways one.
        var left = settings.maxX + Self.gap
        if left + size.width > visible.maxX { left = settings.minX - size.width - Self.gap }
        left = clamp(left, visible.minX + Self.gap, visible.maxX - size.width - Self.gap)
        let bottom = clamp(
            settings.midY - size.height / 2,
            visible.minY + Self.gap,
            visible.maxY - size.height - Self.gap
        )

        panel.setFrame(
            CGRect(x: left, y: bottom, width: size.width, height: size.height), display: true
        )
        panel.orderFrontRegardless()
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}

/// Fixed, and the SwiftUI root is pinned to it. An `NSHostingView` set as a
/// window's content view sizes the window from its intrinsic size, so a card with
/// a flexible height gets a window as tall as the screen will allow.
private let cardSize = CGSize(width: 280, height: 112)

private struct DragCard: View {
    let permission: Permission
    let onDragStateChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            handle
            // Repeats step 3 of `PermissionStepCard.steps` on purpose. This panel is
            // raised at the same moment System Settings comes to the front, so the
            // sheet carrying that step is behind it and the card is the only
            // instruction on screen. The redundancy is across windows, not down a
            // screen — do not cut it as a duplicate.
            Text("Drop it in the \(permission.title) list, then switch utt on.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.small)
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .strokeBorder(Palette.strokeStrong, lineWidth: 0.5)
        }
    }

    /// The row itself is SwiftUI; the AppKit view on top of it does nothing but
    /// turn a mouse drag into a file drag.
    private var handle: some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path))
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("utt").font(Typography.primaryRow)
                Text("Drag me").font(Typography.hint).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Image(systemName: "hand.draw")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, Spacing.extraSmall)
        .padding(.vertical, 6)
        .contentSurface(radius: Radius.medium)
        .overlay(AppBundleDragView(onDragStateChange: onDragStateChange))
    }
}
