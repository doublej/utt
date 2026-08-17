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
        meterLevel: { 0 }
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
