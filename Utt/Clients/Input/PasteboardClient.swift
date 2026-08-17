import AppKit
import Dependencies
import DependenciesMacros
import Foundation
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "pasteboard")

/// Puts text on the pasteboard and synthesizes ⌘V into whatever app is frontmost.
///
/// `CGEvent.post` has **no delivery acknowledgement**, so this cannot report whether
/// the paste actually landed — the reference app's `postCmdV()` returns `true` unconditionally,
/// which makes its second and third fallback strategies dead code. We post once and,
/// if we could not even preflight the permission, leave the text on the clipboard so
/// the user can paste it by hand.
@DependencyClient
struct PasteboardClient: Sendable {
    /// Returns false only when Accessibility (PostEvent) is missing, i.e. when we
    /// know the keystroke was never delivered. A `true` means "posted", not "arrived".
    ///
    /// `keepOnClipboard` leaves the transcript there afterwards instead of putting
    /// back what the user had copied. It is a parameter rather than a settings read
    /// inside the actor because the actor has no business knowing about settings —
    /// and because a test that wants one behaviour should not have to fake the other.
    var paste: @Sendable (_ text: String, _ keepOnClipboard: Bool) async -> Bool = { _, _ in false }
    /// Copy without pasting — used by the menu bar's copy-last-transcript.
    var copy: @Sendable (_ text: String) async -> Void
    /// Best-effort ⌘Z into whatever app is frontmost, for the panel's "Undo".
    /// Returns nothing on purpose: `CGEvent.post` has no delivery acknowledgement
    /// and an app with an empty undo stack ignores it, so there is no honest
    /// success to report — the panel offers the keystroke, not a guarantee.
    var undo: @Sendable () async -> Void
    /// Whoever is about to receive the paste. Lives here rather than in its own
    /// client because "where does the text go" is this client's whole subject.
    var frontmostApp: @Sendable () async -> AppIdentity?
}

struct AppIdentity: Equatable, Sendable {
    let bundleID: String?
    let name: String?
}

extension PasteboardClient: DependencyKey {
    static let liveValue = PasteboardClient(
        paste: { text, keep in await PasteboardActor.shared.paste(text, keepOnClipboard: keep) },
        copy: { text in await PasteboardActor.shared.copy(text) },
        undo: { await PasteboardActor.shared.undo() },
        frontmostApp: {
            await MainActor.run {
                guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
                return AppIdentity(bundleID: app.bundleIdentifier, name: app.localizedName)
            }
        }
    )
}

extension DependencyValues {
    var pasteboard: PasteboardClient {
        get { self[PasteboardClient.self] }
        set { self[PasteboardClient.self] = newValue }
    }
}

private actor PasteboardActor {
    static let shared = PasteboardActor()

    /// How long to leave our text on the pasteboard before restoring the user's.
    /// Long enough for the target app to service the paste, short enough that the
    /// clipboard does not visibly belong to us.
    private static let restoreDelay = Duration.milliseconds(500)

    func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    func paste(_ text: String, keepOnClipboard: Bool) async -> Bool {
        guard CGPreflightPostEventAccess() else {
            log.error("PostEvent access missing — leaving text on the pasteboard instead")
            copy(text)
            return false
        }

        let board = NSPasteboard.general
        let previous = board.string(forType: .string)

        // clearContents() is what bumps changeCount; setString does not bump it again.
        // So this return value is the one to compare against on restore.
        let ourChange = board.clearContents()
        board.setString(text, forType: .string)

        postCommand(Self.vKey)

        // Asked to leave it there, so there is nothing to wait for and nothing to
        // put back — returning here is also what makes "leave the transcript on the
        // clipboard" mean it, rather than meaning it for half a second.
        guard !keepOnClipboard else { return true }

        try? await Task.sleep(for: Self.restoreDelay)

        // Only restore if nobody else wrote to the pasteboard in the meantime —
        // otherwise we would clobber whatever the user copied during the window.
        guard board.changeCount == ourChange else {
            log.debug("pasteboard changed under us (\(board.changeCount) != \(ourChange)); not restoring")
            return true
        }
        if let previous {
            board.clearContents()
            board.setString(previous, forType: .string)
        }
        return true
    }

    /// Undo is not ours to confirm: the keystroke goes to whoever has focus, and
    /// an app with nothing on its undo stack simply does nothing with it.
    func undo() {
        guard CGPreflightPostEventAccess() else {
            log.error("PostEvent access missing — cannot undo")
            return
        }
        postCommand(Self.zKey)
    }

    private static let vKey: CGKeyCode = 9
    private static let zKey: CGKeyCode = 6

    private func postCommand(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            else { continue }
            event.flags = .maskCommand
            SyntheticKeyEvent.mark(event)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
