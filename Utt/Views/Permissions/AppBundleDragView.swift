import AppKit
import SwiftUI

/// Transparent overlay that turns a mouse drag into a drag of utt's own `.app`
/// bundle, so it can be dropped into a System Settings privacy list.
struct AppBundleDragView: NSViewRepresentable {
    let onDragStateChange: (Bool) -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.onDragStateChange = onDragStateChange
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.onDragStateChange = onDragStateChange
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var onDragStateChange: ((Bool) -> Void)?

    private var mouseDownAt: NSPoint?
    private var dragging = false

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownAt = convert(event.locationInWindow, from: nil)
        dragging = false
    }

    /// A few points of slack, so a click that wobbles is still a click.
    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = mouseDownAt else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        dragging = true
        beginDrag(with: event, from: point)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownAt = nil
        dragging = false
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    /// Otherwise holding ⌘ or ⌥ mid-drag turns the copy into a move or a link, and
    /// System Settings refuses the drop.
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragStateChange?(true)
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        onDragStateChange?(false)
        mouseDownAt = nil
        dragging = false
    }

    private func beginDrag(with event: NSEvent, from point: NSPoint) {
        let url = Bundle.main.bundleURL
        let item = NSDraggingItem(pasteboardWriter: AppBundlePasteboardWriter(url: url))
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 56, height: 56)
        item.setDraggingFrame(
            NSRect(x: point.x - 28, y: point.y - 28, width: 56, height: 56), contents: icon
        )
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }
}

/// A bare `.fileURL` is not enough in practice: the privacy list is the old
/// System Preferences drop target and it only takes the drag when the pasteboard
/// looks like one Finder wrote — which means all five of these types.
private final class AppBundlePasteboardWriter: NSObject, NSPasteboardWriting {
    private static let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let promisedFileURL = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")

    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, Self.filenames, Self.promisedFileURL, .string]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL, .URL, Self.promisedFileURL: url.absoluteString
        case Self.filenames: [url.path]
        case .string: url.path
        default: nil
        }
    }
}
