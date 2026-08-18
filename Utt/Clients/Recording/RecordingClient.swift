import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "recording")

/// Orchestrates a recording. Deliberately thin — the reference app's equivalent is a
/// single 1,700-line actor and is its least maintainable file, so capture, device
/// enumeration and media control live in their own types alongside this one.
@DependencyClient
struct RecordingClient: Sendable {
    /// Keeps the engine running between recordings so a clip can begin before the
    /// keypress that asked for it. Idempotent, and safe to call mid-recording:
    /// a change of mind about pre-roll never interrupts a clip in progress.
    /// `keepWarm` prevents IdleObserver-triggered suspends when true.
    var arm: @Sendable (_ enabled: Bool, _ microphoneUIDs: [String], _ keepWarm: Bool) async -> Void
    /// Begins writing to a fresh file in the recordings directory. The UIDs are a
    /// priority list; the first device that is present wins, and an empty list —
    /// or one where nothing is plugged in — follows the system default input.
    var start: @Sendable (_ microphoneUIDs: [String]) async throws -> Void
    /// Stops and returns the finished file, or nil if nothing usable was captured.
    var stop: @Sendable () async -> RecordingResult?
    /// Stops and throws the audio away — ESC, or a press below the minimum time.
    var cancel: @Sendable () async -> Void
    /// Instantaneous input level, 0...1, for the VU meter and indicator.
    var meterLevel: @Sendable () async -> Float = { 0 }
}

struct RecordingResult: Equatable, Sendable {
    let url: URL
    let duration: TimeInterval
    /// Peak amplitude over the whole recording, 0...1.
    ///
    /// Worth surfacing: a clip peaking around 0.02 (−34 dBFS) transcribes to an
    /// **empty string** rather than failing, so a quiet mic looks like a broken app.
    let peak: Float

    /// Below this, warn the user rather than letting them think transcription broke.
    static let quietThreshold: Float = 0.05

    var isSuspiciouslyQuiet: Bool { peak < Self.quietThreshold }
}

extension RecordingClient: DependencyKey {
    static let liveValue: RecordingClient = {
        let recorder = Recorder()
        IdleObserver.observe(
            suspend: { Task { await recorder.suspend() } },
            resume: { Task { await recorder.resume() } }
        )
        return RecordingClient(
            arm: { enabled, uids, keepWarm in await recorder.arm(enabled, microphoneUIDs: uids, keepWarm: keepWarm) },
            start: { uids in try await recorder.start(microphoneUIDs: uids) },
            stop: { await recorder.stop() },
            cancel: { await recorder.cancel() },
            meterLevel: { await recorder.meterLevel() }
        )
    }()
}

extension DependencyValues {
    var recording: RecordingClient {
        get { self[RecordingClient.self] }
        set { self[RecordingClient.self] = newValue }
    }
}

private actor Recorder {
    private let capture = CaptureController()
    private var currentURL: URL?
    private var armed = false
    private var armedUIDs: [String] = []
    /// When true, IdleObserver-triggered suspends are ignored and the mic stays warm.
    private var keepWarm = false

    func arm(_ enabled: Bool, microphoneUIDs: [String], keepWarm: Bool) {
        armed = enabled
        armedUIDs = microphoneUIDs
        self.keepWarm = keepWarm
        // A settings edit mid-recording waits: tearing the engine down here would
        // truncate the clip the user is still speaking into.
        guard currentURL == nil else { return }
        if enabled { openArmed() } else { capture.stop() }
    }

    func start(microphoneUIDs: [String]) throws {
        discardInFlight()
        let url = try URL.uttRecordings
            .appendingPathComponent("utt-\(UUID().uuidString).wav")

        try capture.start(writingTo: url, microphoneUIDs: microphoneUIDs)
        currentURL = url
    }

    func stop() async -> RecordingResult? {
        guard let url = currentURL else { return nil }
        // The block being filled when the hotkey came up is still in flight; closing
        // now would eat the final consonant.
        try? await Task.sleep(for: capture.stopGrace)
        let result = end()
        currentURL = nil

        guard result.duration >= ParakeetClient.minimumDuration else {
            log.debug("discarding \(result.duration, format: .fixed(precision: 2))s clip — under the decoder floor")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return RecordingResult(url: url, duration: result.duration, peak: result.peak)
    }

    func cancel() {
        discardInFlight()
    }

    func meterLevel() -> Float { capture.currentLevel }

    /// Nobody is at the machine, so give the microphone back — and with it the
    /// system indicator that an armed engine otherwise keeps lit indefinitely.
    /// Skipped when `keepWarm` is true — the user has opted into the always-lit indicator.
    func suspend() {
        guard !keepWarm, currentURL == nil else { return }
        capture.stop()
    }

    func resume() {
        guard armed, currentURL == nil else { return }
        openArmed()
    }

    private func openArmed() {
        do { try capture.arm(microphoneUIDs: armedUIDs) } catch {
            // Pre-roll is an optimisation; losing it must not stop the app from
            // recording the ordinary way when the hotkey is pressed.
            log.error("could not arm pre-roll: \(error.localizedDescription)")
        }
    }

    /// Ends the clip, staying armed when pre-roll is on so the next one keeps it.
    private func end() -> CaptureController.Capture {
        armed ? capture.finish() : capture.stop()
    }

    private func discardInFlight() {
        guard let url = currentURL else { return }
        _ = end()
        try? FileManager.default.removeItem(at: url)
        currentURL = nil
    }
}
