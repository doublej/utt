import Foundation
@testable import utt

/// Clients that do nothing and say so. `@DependencyClient`'s generated
/// `testValue` traps on any unimplemented endpoint, which is the right default
/// but makes every test a list of stubs — these cover the endpoints the feature
/// tests genuinely do not care about.
extension RecordingClient {
    static let quiet = RecordingClient(
        arm: { _, _, _ in },
        start: { _ in },
        stop: { nil },
        cancel: {},
        meterLevel: { 0 },
        reconnect: { _ in },
        tee: { _ in }
    )
}

extension LiveTranscriptionClient {
    /// The setting is off by default, so `start` is never reached in the feature
    /// tests — but a test that turns it on gets a session that hears nothing.
    static let quiet = LiveTranscriptionClient(
        start: { .finished },
        feed: { _ in },
        finish: {},
        isDownloaded: { false }
    )
}

extension TranscriptionClient {
    static let quiet = TranscriptionClient(
        transcribe: { _, _, _ in "" },
        prepare: { _, _ in .finished },
        isDownloaded: { _, _ in true },
        isReady: { _, _ in true },
        unload: {}
    )
}

extension TranscriptCleanupClient {
    /// The setting is off by default, so nothing here is reached — the stub exists
    /// because the reducer captures the client whether or not it will call it.
    static let quiet = TranscriptCleanupClient(prewarm: {}, clean: { _ in .skipped(.unavailable) })
}

extension PasteboardClient {
    static let quiet = PasteboardClient(
        paste: { _, _ in true },
        copy: { _ in },
        undo: {},
        frontmostApp: { nil }
    )
}

extension SleepManagementClient {
    static let quiet = SleepManagementClient(preventSleep: { _ in }, allowSleep: {})
}

extension MediaControlClient {
    static let quiet = MediaControlClient(mute: {}, unmute: {})
}
