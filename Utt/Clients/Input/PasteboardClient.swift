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
    var paste: @Sendable (_ text: String) async -> Bool = { _ in false }
    /// Copy without pasting — used by the menu bar's copy-last-transcript.
    var copy: @Sendable (_ text: String) async -> Void
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
        paste: { text in await PasteboardActor.shared.paste(text) },
        copy: { text in await PasteboardActor.shared.copy(text) },
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

    func paste(_ text: String) async -> Bool {
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

        postCommandV()

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

    private func postCommandV() {
        let vKey: CGKeyCode = 9
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: down)
            else { continue }
            event.flags = .maskCommand
            SyntheticKeyEvent.mark(event)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
