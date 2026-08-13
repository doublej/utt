import AppKit
import CoreGraphics
import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "keytap")

/// Watches the global keyboard through a CGEventTap.
///
/// Events arrive on a **single serial `AsyncStream`**. This is not incidental: a
/// `Task { await send(...) }` spawned per key event can reorder press and release,
/// because independent tasks have no ordering guarantee. utty hit exactly this and
/// papered over it with a hand-rolled `dispatchChain`. One stream, one consumer.
@DependencyClient
struct KeyEventMonitorClient: Sendable {
    /// Ordered key events. Finishes only when the client is torn down.
    var events: @Sendable () -> AsyncStream<KeyEvent> = { .finished }
    /// Chords the tap should swallow, so a hotkey does not also reach the
    /// frontmost app. Requires `.defaultTap`. Matching is on key **and** modifiers:
    /// suppressing a bare keycode would swallow ⌘V system-wide the moment someone
    /// picks ⌥⇧V as a shortcut.
    var setSuppressed: @Sendable (_ chords: [HotKey]) -> Void
    var start: @Sendable () -> Void
    var stop: @Sendable () -> Void
    /// False when `tapCreate` returned nil — almost always missing Input Monitoring.
    var isRunning: @Sendable () -> Bool = { false }
}

extension KeyEventMonitorClient: DependencyKey {
    static let liveValue: KeyEventMonitorClient = {
        let monitor = KeyEventMonitor()
        return KeyEventMonitorClient(
            events: { monitor.events },
            setSuppressed: { monitor.setSuppressed($0) },
            start: { monitor.start() },
            stop: { monitor.stop() },
            isRunning: { monitor.isRunning }
        )
    }()

    static let testValue = KeyEventMonitorClient()
}

extension DependencyValues {
    var keyEventMonitor: KeyEventMonitorClient {
        get { self[KeyEventMonitorClient.self] }
        set { self[KeyEventMonitorClient.self] = newValue }
    }
}

/// `@unchecked Sendable` is audited, not lazy: every mutable field is guarded by
/// `lock`, and the tap callback only ever touches those guarded fields. A barrier
/// `DispatchQueue` would *not* satisfy the Swift 6 compiler here, and pretending
/// otherwise is how you get a data race that only shows up under load.
final class KeyEventMonitor: @unchecked Sendable {
    let events: AsyncStream<KeyEvent>
    private let continuation: AsyncStream<KeyEvent>.Continuation

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var suppressed: [HotKey] = []

    var isRunning: Bool { lock.withLock { tap != nil } }

    init() {
        // .unbounded: dropping a keyUp would strand the state machine mid-recording.
        (events, continuation) = AsyncStream<KeyEvent>.makeStream(bufferingPolicy: .unbounded)
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // A tap does not survive sleep. Recreating is the only reliable fix;
            // tapEnable on a dead port silently does nothing.
            log.info("woke from sleep — recreating tap")
            self?.restart()
        }
    }

    func setSuppressed(_ chords: [HotKey]) {
        lock.withLock { suppressed = chords.filter { $0.key != nil } }
    }

    func start() {
        lock.lock()
        guard tap == nil else { lock.unlock(); return }
        lock.unlock()

        // .cgSessionEventTap, not .cghidEventTap: strictly less privileged and
        // sufficient. (CGEvent.h:269 claims HID taps are root-only; that text dates
        // to 10.4 and is stale — the reference app ships HID taps — but session tap
        // is the right default regardless.)
        //
        // .defaultTap, not .listenOnly: the callback must be able to return nil to
        // swallow the hotkey. utty used .listenOnly and therefore could never stop
        // the hotkey from also reaching the frontmost app.
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Nil here is nearly always missing Input Monitoring. Note that a tap
            // created before the grant stays dead forever — restart() is required,
            // tapEnable is not enough.
            log.error("tapCreate returned nil — Input Monitoring not granted?")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        lock.withLock {
            tap = port
            runLoopSource = source
        }
        log.info("event tap running")
    }

    func stop() {
        let (port, source) = lock.withLock { (tap, runLoopSource) }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        lock.withLock {
            tap = nil
            runLoopSource = nil
        }
    }

    func restart() {
        stop()
        start()
    }

    /// What is *still held* after a CG event, which is what `HotKeyProcessor` consumes:
    /// every one of its releases is written `key: nil`.
    ///
    /// Only `.keyDown` carries a key. A `.keyUp` used to report the key that had just
    /// been released, which made a press and its release identical events — so the
    /// processor never saw a key released, and `isDirty` (set by any unrelated key,
    /// i.e. by ordinary typing) could only be cleared by lifting the last *modifier*.
    /// The first hotkey press after typing was swallowed to clear that flag, and only
    /// the second one recorded.
    ///
    /// `.flagsChanged` carries no key either — its `keyCode` is the modifier itself.
    ///
    /// NSEvent.ModifierFlags and CGEventFlags share raw bit layout for the four
    /// general masks plus `.function`, so one decoder covers both sources.
    static func chord(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> KeyEvent {
        KeyEvent(
            key: type == .keyDown ? Key(rawValue: UInt16(keyCode)) : nil,
            modifiers: Modifiers.from(carbonFlags: flags.rawValue)
        )
    }

    /// Called on the run loop thread from the C callback. Returns true to swallow.
    fileprivate func handle(
        type: CGEventType, keyCode: Int64, flags: CGEventFlags, isSynthetic: Bool
    ) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS kills taps that take too long, and again on some user input.
            // Re-enabling in place is enough for these two; sleep needs a full restart.
            log.notice("tap disabled (\(type.rawValue)) — re-enabling")
            if let port = lock.withLock({ tap }) { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        default:
            break
        }

        // `PasteboardActor` posts its own Command-V into this same event-tap
        // stream. Letting it reach the processor makes the processor dirty, but
        // synthetic events never produce the final all-keys-up event that clears
        // that state; the next real hotkey is then swallowed.
        if isSynthetic { return false }

        continuation.yield(Self.chord(type: type, keyCode: keyCode, flags: flags))

        // Suppression asks a different question than the processor does: which key is
        // this event *about*, held or not. The key-up of a swallowed hotkey has to be
        // swallowed too, or the frontmost app gets a release it never saw pressed.
        //
        // A modifier-only hotkey is never suppressed: swallowing a bare ⌥ would
        // break every other shortcut that uses it.
        guard type != .flagsChanged else { return false }
        let key = Key(rawValue: UInt16(keyCode))
        let pressed = Modifiers.from(carbonFlags: flags.rawValue).erasingSides()
        return lock.withLock {
            suppressed.contains { $0.key == key && $0.modifiers.erasingSides() == pressed }
        }
    }

    deinit {
        continuation.finish()
    }
}

/// C callback — runs on the run loop thread, so it must not hop actors or allocate
/// unnecessarily. Every field of the event is snapshotted to a value here; a
/// `CGEvent` is not `Sendable` and must never cross an isolation boundary.
private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    let swallow = monitor.handle(
        type: type,
        keyCode: keyCode,
        flags: flags,
        isSynthetic: SyntheticKeyEvent.isMarked(event)
    )
    return swallow ? nil : Unmanaged.passUnretained(event)
}
