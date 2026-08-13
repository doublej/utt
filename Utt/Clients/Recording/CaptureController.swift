import AVFoundation
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "capture")

/// Owns the `AVAudioEngine` and writes 16 kHz mono Int16 to disk.
///
/// **This type must not be actor- or main-actor-isolated.** The tap block runs on a
/// real-time audio thread; if the closure inherits main-actor isolation (which it
/// does when written inline in top-level code or in a `@MainActor` type), Swift 6
/// traps in `_swift_task_checkIsolatedSwift` the first time a buffer arrives —
/// `EXC_BREAKPOINT` inside `dispatch_assert_queue_fail`. Verified the hard way in
/// the Phase 0 spike.
///
/// Never let an `AVAudioPCMBuffer` escape this type: it is not `Sendable`. Snapshot
/// to values (peak, frame counts) before anything crosses an isolation boundary.
///
/// The engine has two modes. *Armed* keeps it running with no file open, so the tap
/// fills the pre-roll ring; *recording* points the same already-warm tap at a file.
/// Only the caller's serialization (a single actor) keeps `open`/`close`/`start`
/// from overlapping — everything the tap touches is behind `lock` instead.
final class CaptureController: @unchecked Sendable {
    /// Parakeet wants 16 kHz mono. Real hardware rarely obliges — AirPods present
    /// 24 kHz — so the resample path is exercised on ordinary setups, not just edge cases.
    static let targetSampleRate: Double = 16000

    /// How much audio from before the keypress lands in the file. Long enough to
    /// catch a word already in flight, short enough not to pick up the tail of
    /// whatever was said before it.
    private static let preRollFrames = Int(targetSampleRate * 0.45)
    private static let ringFrames = Int(targetSampleRate)

    private let engine = AVAudioEngine()
    private let lock = NSLock()

    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var targetFormat: AVAudioFormat?
    private var peak: Float = 0
    private var meterLevel: Float = 0
    private var framesWritten = 0
    private var ring = PreRollBuffer(capacity: ringFrames)
    private var tapInterval: Double = 0
    private var lastTapAt: UInt64 = 0
    private var tapSession: UUID?
    private var receivedTap = false

    /// Only touched from the owning actor, never from the tap.
    private var isOpen = false
    private var openUID: String?

    enum Failure: Error {
        case formatUnavailable
        case converterUnavailable
    }

    /// Peak amplitude 0...1 and the exact number of frames on disk. Frames beat a
    /// wall clock here: with pre-roll the file is ~0.45 s longer than the keypress
    /// suggests, and the decoder floor has to be checked against the real length.
    struct Capture: Sendable {
        let peak: Float
        let frames: Int

        var duration: TimeInterval { Double(frames) / CaptureController.targetSampleRate }
    }

    /// Starts the engine with no file open, so the ring fills in the background and
    /// the next `start` already has half a second of audio in hand.
    func arm(microphoneUID: String?) throws {
        guard lock.withLock({ file }) == nil else { return }
        guard !isOpen || openUID != microphoneUID else { return }
        close()
        try open(microphoneUID)
    }

    func start(writingTo url: URL, microphoneUID: String?) throws {
        // A cold start, or one against a different microphone than the ring was
        // filled from, has to reopen — pre-roll from the wrong device is worse
        // than none.
        if !isOpen || openUID != microphoneUID {
            close()
            try open(microphoneUID)
        }
        guard let target = lock.withLock({ targetFormat }) else { throw Failure.formatUnavailable }
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: target.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )
        // The pre-roll write happens *inside* the lock, which means it can briefly
        // block the audio thread. That is the intended trade: releasing the lock
        // between draining the ring and installing the file would drop one tap's
        // worth of audio into the seam and leave an audible gap. It is a single
        // ~29 KB write against a block period of 20 ms or more.
        lock.withLock {
            peak = 0
            meterLevel = 0
            framesWritten = writePreRoll(ring.tail(Self.preRollFrames), to: audioFile, format: target)
            file = audioFile
        }
    }

    /// Closes the file but leaves the engine armed, so the next recording keeps its
    /// pre-roll and does not pay for opening the device again.
    @discardableResult
    func finish() -> Capture {
        lock.withLock {
            file = nil // closing the AVAudioFile is what flushes it
            ring.reset()
            return Capture(peak: peak, frames: framesWritten)
        }
    }

    /// Closes the file *and* shuts the engine down, releasing the microphone and
    /// putting out the system's mic-in-use indicator.
    @discardableResult
    func stop() -> Capture {
        let capture = finish()
        close()
        return capture
    }

    /// Instantaneous level for the VU meter and the indicator's fill brightness.
    var currentLevel: Float { lock.withLock { meterLevel } }

    /// How long to keep capturing after the hotkey comes up, derived from the tap
    /// cadence this device is actually running at.
    var stopGrace: Duration {
        StopGrace.period(tapInterval: .seconds(lock.withLock { tapInterval }))
    }

    private func open(_ uid: String?) throws {
        let input = engine.inputNode
        selectInput(uid, on: input)
        // Read the format after switching devices, and from the *input* side:
        // `outputFormat` keeps reporting the previous device's rate after
        // `setDeviceID`, and a tap installed with it never fires at all.
        let hardware = input.inputFormat(forBus: 0)

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { throw Failure.formatUnavailable }

        guard let converter = AVAudioConverter(from: hardware, to: target) else {
            throw Failure.converterUnavailable
        }

        let session = UUID()
        lock.withLock {
            self.targetFormat = target
            self.converter = converter
            self.peak = 0
            self.meterLevel = 0
            self.framesWritten = 0
            self.tapInterval = 0
            self.lastTapAt = 0
            self.tapSession = session
            self.receivedTap = false
            self.ring.reset()
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: hardware) { [weak self] buffer, _ in
            self?.accept(buffer, hardwareSampleRate: hardware.sampleRate)
        }

        engine.prepare()
        try engine.start()
        isOpen = true
        openUID = uid
        log.info("capture open: \(Int(hardware.sampleRate))Hz \(hardware.channelCount)ch")
        warnIfTapIsMissing(for: session)
    }

    private func close() {
        guard isOpen else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isOpen = false
        openUID = nil
        lock.withLock {
            self.file = nil
            self.converter = nil
            self.tapSession = nil
        }
    }

    /// Points the input node at a specific device. A `nil` UID — or one whose device is
    /// unplugged — falls back to the system default, set explicitly because the audio unit
    /// keeps its last device: "Default" would otherwise keep the previous microphone.
    private func selectInput(_ uid: String?, on input: AVAudioInputNode) {
        let selected = uid.flatMap { CoreAudioDevices.deviceID(forUID: $0) }
        if uid != nil, selected == nil {
            log.notice("microphone \(uid ?? "", privacy: .public) is gone; using default")
        }
        guard let deviceID = selected ?? CoreAudioDevices.defaultInputID() else { return }
        do {
            try input.auAudioUnit.setDeviceID(deviceID)
            log.info("capture input device set: \(deviceID)")
        } catch {
            log.error("could not select input device: \(error.localizedDescription)")
        }
    }

    private func accept(_ buffer: AVAudioPCMBuffer, hardwareSampleRate: Double) {
        lock.withLock { receivedTap = true }
        recordCadence()
        guard let target = lock.withLock({ targetFormat }),
              let converter = lock.withLock({ converter })
        else { return }

        if let channel = buffer.floatChannelData?[0] {
            var framePeak: Float = 0
            for frame in 0..<Int(buffer.frameLength) {
                framePeak = max(framePeak, abs(channel[frame]))
            }
            lock.withLock {
                peak = max(peak, framePeak)
                // Simple decay so the meter falls smoothly instead of flickering.
                meterLevel = max(framePeak, meterLevel * 0.85)
            }
        }

        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * target.sampleRate / hardwareSampleRate) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        let input = InputBox(buffer)
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            guard let next = input.take() else { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData
            return next
        }
        guard error == nil, converted.frameLength > 0 else { return }
        deliver(converted)
    }

    /// Converted audio goes to the file while recording, and to the ring otherwise.
    /// It never goes to both: while recording, the ring would only accumulate audio
    /// that has already been written, and the next clip would repeat it.
    private func deliver(_ converted: AVAudioPCMBuffer) {
        lock.withLock {
            guard let file else {
                guard let channel = converted.int16ChannelData?[0] else { return }
                ring.append(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
                return
            }
            do {
                try file.write(from: converted)
                framesWritten += Int(converted.frameLength)
            } catch {
                log.error("write failed: \(error.localizedDescription)")
            }
        }
    }

    private func recordCadence() {
        let nanoseconds = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            defer { lastTapAt = nanoseconds }
            guard lastTapAt > 0, nanoseconds > lastTapAt else { return }
            let delta = Double(nanoseconds - lastTapAt) / 1_000_000_000
            // An exponential moving average is a rolling window that costs no
            // allocation — which is what the audio thread requires.
            tapInterval = tapInterval > 0 ? tapInterval * 0.9 + delta * 0.1 : delta
        }
    }

    private func warnIfTapIsMissing(for session: UUID) {
        Task.detached { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.isTapMissing(for: session) else { return }
            log.error("capture tap delivered no buffers within 500ms")
        }
    }

    private func isTapMissing(for session: UUID) -> Bool {
        lock.withLock { tapSession == session && !receivedTap }
    }
}
