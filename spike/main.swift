import AppKit
import AVFoundation
import CoreGraphics
import Foundation

// utt Phase 0 spike — proves event tap / paste / mic before any domain modelling.
// Writes results to $SPIKE_OUT (JSON lines). Launched via `open Spike.app` so TCC
// attributes the prompts to this bundle, not to Terminal.

let out = ProcessInfo.processInfo.environment["SPIKE_OUT"]
    ?? NSHomeDirectory() + "/spike-result.jsonl"

func emit(_ check: String, _ ok: Bool, _ detail: String = "") {
    let line = #"{"check":"\#(check)","ok":\#(ok),"detail":"\#(detail.replacingOccurrences(of: "\"", with: "'"))"}"# + "\n"
    if let h = FileHandle(forWritingAtPath: out) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    NSLog("SPIKE %@ ok=%d %@", check, ok ? 1 : 0, detail)
}

FileManager.default.createFile(atPath: out, contents: nil)

// Become a real (accessory) NSApplication before touching TCC. A bundle that never
// spins up NSApp is not treated as an app by the Privacy & Security UI.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()
emit("nsapp", true, Bundle.main.bundlePath)

// ── 1. permissions ────────────────────────────────────────────────────────────
// CGPreflight/Request*EventAccess — not AXIsProcessTrusted, which gates a different privilege.
let listenPre = CGPreflightListenEventAccess()
let postPre = CGPreflightPostEventAccess()
emit("preflight.listen", listenPre, "before request")
emit("preflight.post", postPre, "before request")
if !listenPre { _ = CGRequestListenEventAccess() }
if !postPre { _ = CGRequestPostEventAccess() }

// TCC grants land asynchronously after the user flips the switch; poll rather than assume.
var waited = 0.0
while !(CGPreflightListenEventAccess() && CGPreflightPostEventAccess()), waited < 120 {
    Thread.sleep(forTimeInterval: 1); waited += 1
}
let listenOK = CGPreflightListenEventAccess()
let postOK = CGPreflightPostEventAccess()
emit("granted.listen", listenOK, "after \(Int(waited))s")
emit("granted.post", postOK, "after \(Int(waited))s")
guard listenOK, postOK else { emit("abort", false, "permissions not granted"); exit(1) }

// ── 2. session event tap, .defaultTap so the callback can swallow ─────────────
/// AVAudioConverter's input block runs synchronously on the calling thread; the box
/// only exists to satisfy Swift 6's capture rules.
final class Flag: @unchecked Sendable { var value = false }

/// Audio capture must NOT be main-actor isolated. Top-level Swift code is
/// `@MainActor`, so a tap closure written inline up there inherits that isolation
/// and `_swift_task_checkIsolatedSwift` traps the moment the real-time audio
/// thread calls it (EXC_BREAKPOINT in dispatch_assert_queue_fail). Owning the
/// state in a plain class keeps the callback nonisolated.
final class Capture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var target: AVAudioFormat?
    private var peak: Float = 0

    /// Returns the hardware input format actually in use.
    func start(to url: URL) throws -> AVAudioFormat {
        let input = engine.inputNode
        let hw = input.outputFormat(forBus: 0)
        // 16 kHz mono Int16 — what Parakeet wants. AirPods come in at 24 kHz,
        // so the resample path is not optional.
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: hw, to: target)
        else { throw NSError(domain: "spike", code: 1) }
        self.target = target
        self.converter = converter
        self.file = try AVAudioFile(forWriting: url, settings: target.settings,
                                    commonFormat: .pcmFormatInt16, interleaved: false)

        input.installTap(onBus: 0, bufferSize: 1024, format: hw) { [self] buffer, _ in
            accept(buffer, hwSampleRate: hw.sampleRate)
        }
        try engine.start()
        return hw
    }

    private func accept(_ buffer: AVAudioPCMBuffer, hwSampleRate: Double) {
        guard let target, let converter, let file else { return }
        if let ch = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(ch[i])) }
        }
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / hwSampleRate) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
        let supplied = Flag()
        var err: NSError?
        converter.convert(to: converted, error: &err) { _, status in
            if supplied.value { status.pointee = .noDataNow; return nil }
            supplied.value = true; status.pointee = .haveData; return buffer
        }
        if err == nil, converted.frameLength > 0 { try? file.write(from: converted) }
    }

    func stop() -> Float {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        file = nil // flush
        return peak
    }
}

final class TapBox: @unchecked Sendable {
    var seen: [(code: Int64, type: CGEventType)] = []
    var swallowKeyCode: Int64 = -1
    var swallowed = 0
}
let box = TapBox()

let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    | (1 << CGEventType.flagsChanged.rawValue)

let callback: CGEventTapCallBack = { _, type, event, refcon in
    let box = Unmanaged<TapBox>.fromOpaque(refcon!).takeUnretainedValue()
    // Snapshot fields to values immediately — never carry CGEvent across isolation.
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    box.seen.append((code, type))
    if type == .keyDown || type == .keyUp, code == box.swallowKeyCode {
        box.swallowed += 1
        return nil // proves .defaultTap can actually suppress delivery
    }
    return Unmanaged.passUnretained(event)
}

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap,
    options: .defaultTap, eventsOfInterest: CGEventMask(mask),
    callback: callback, userInfo: Unmanaged.passUnretained(box).toOpaque()
) else {
    emit("tap.create", false, "tapCreate returned nil despite ListenEventAccess")
    exit(1)
}
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
emit("tap.create", true, "cgSessionEventTap + defaultTap")

func pump(_ seconds: Double) { CFRunLoopRunInMode(.defaultMode, seconds, false) }

// ── 3. tap receives synthesized keys ─────────────────────────────────────────
let src = CGEventSource(stateID: .hidSystemState)
@MainActor func post(_ code: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cgSessionEventTap)
    }
}

let kF13: CGKeyCode = 105
box.seen.removeAll()
post(kF13)
pump(1.0)
let sawF13 = box.seen.contains { $0.code == Int64(kF13) }
emit("tap.receives", sawF13, "F13 events seen=\(box.seen.count)")

// ── 4. TextEdit: paste lands, and a swallowed key does not ───────────────────
// TextEdit must already be frontmost with an empty untitled document (harness does that).
guard let te = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.apple.TextEdit").first
else { emit("textedit.running", false, "TextEdit not running"); exit(1) }
te.activate()
Thread.sleep(forTimeInterval: 1.0)
emit("textedit.running", true, "activated")

// 4a. type 'a' with the tap passing it through → should appear
let kA: CGKeyCode = 0
box.swallowKeyCode = -1
post(kA)
pump(0.6)

// 4b. type 'b' with the tap swallowing it → should NOT appear
let kB: CGKeyCode = 11
box.swallowKeyCode = Int64(kB)
box.swallowed = 0
post(kB)
pump(0.6)
emit("tap.swallow.fired", box.swallowed > 0, "callback returned nil \(box.swallowed)x")
box.swallowKeyCode = -1

// 4c. paste via CGEvent ⌘V
let pb = NSPasteboard.general
let marker = "utt-spike-paste-ok"
// clearContents() is what bumps changeCount — setString does not bump it again.
// So the value to remember for the restore guard is clearContents()'s return.
let myChange = pb.clearContents()
pb.setString(marker, forType: .string)
emit("pasteboard.write", pb.changeCount == myChange && pb.string(forType: .string) == marker,
     "changeCount=\(myChange) (bumped by clearContents, not setString)")

let kV: CGKeyCode = 9
post(kV, flags: .maskCommand)
pump(1.0)
emit("paste.posted", true, "cmd-V posted; harness verifies TextEdit contents")

// ⌘S so the harness can read the result off disk — no AppleEvents anywhere.
let kS: CGKeyCode = 1
post(kS, flags: .maskCommand)
pump(1.5)

// changeCount guard: only restore if nobody else wrote to the pasteboard meanwhile.
emit("pasteboard.changecount.stable", pb.changeCount == myChange, "now \(pb.changeCount)")

// ── 5. microphone capture ────────────────────────────────────────────────────
// Do NOT block the main thread here. A semaphore wait starves the run loop that
// TCC needs to present its prompt, so the dialog never appears and the callback
// never fires. Pump the run loop instead. Same rule applies in the real app.
let micResult = Flag()
let micDone = Flag()
AVCaptureDevice.requestAccess(for: .audio) { micResult.value = $0; micDone.value = true }
var micWait = 0.0
while !micDone.value, micWait < 120 {
    CFRunLoopRunInMode(.defaultMode, 0.2, false); micWait += 0.2
}
let micGranted = micResult.value
emit("mic.granted", micGranted, "requestAccess resolved in \(String(format: "%.1f", micWait))s")

if micGranted {
    let wavURL = URL(fileURLWithPath: (out as NSString).deletingLastPathComponent + "/spike-mic.wav")
    let capture = Capture()
    do {
        let hw = try capture.start(to: wavURL)
        emit("mic.engine.start", true, "hw \(Int(hw.sampleRate))Hz \(hw.channelCount)ch")
        pump(3.0)
        let peak = capture.stop()
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: wavURL.path)[.size]) as? Int) ?? 0
        emit("mic.capture", peak > 0.0001 && bytes > 4096,
             "peak=\(String(format: "%.4f", peak)) bytes=\(bytes)")
    } catch {
        emit("mic.engine.start", false, "\(error)")
    }
}

emit("done", true, "spike complete")
exit(0)
