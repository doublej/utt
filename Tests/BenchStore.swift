import AppKit
import ComposableArchitecture
import Foundation
import UttCore
@testable import utt

/// The store the bench drives: the real `AppFeature`, with the system half of its
/// dependencies swapped for ones that touch nothing outside this process, and a
/// stopwatch on either side of the reducer.
extension BenchSession {
    static func makeStore(_ marks: BenchMarks, _ recorder: BenchRecorder) -> StoreOf<AppFeature> {
        Store(initialState: AppFeature.State()) {
            Reduce<AppFeature.State, AppFeature.Action> { _, action in
                marks.before(action)
                return .none
            }
            AppFeature()
            Reduce<AppFeature.State, AppFeature.Action> { _, action in
                marks.after(action)
                return .none
            }
        } withDependencies: {
            $0.continuousClock = ContinuousClock()
            $0.date = DateGenerator { Date() }
            $0.recording = recorder.client
            $0.transcription = .liveValue
            $0.liveTranscription = live(marks)
            $0.transcriptCleanup = .liveValue
            $0.extensionFilters = .liveValue
            $0.extensionJobs = .liveValue
            $0.extensions = extensions(marks)
            $0.pasteboard = pasteboard(marks)
            // The system half stays out: no tap, no listener, no login item, no
            // muting the speakers or holding the Mac awake, no events sent anywhere.
            $0.keyEventMonitor = KeyEventMonitorClient(
                events: { .finished }, setSuppressed: { _ in }, start: {}, stop: {}, isRunning: { false }
            )
            $0.apiServer = ApiServerClient(apply: { _, _ in }, states: { .finished })
            $0.appPresence = AppPresenceClient(setOpensAtLogin: { _ in }, setShowsDockIcon: { _ in })
            $0.sleepManagement = .quiet
            $0.mediaControl = .quiet
            $0.soundEffects = SoundEffectClient(play: { _, _ in })
            $0.analytics = AnalyticsClient(send: { _ in })
        }
    }

    private static func live(_ marks: BenchMarks) -> LiveTranscriptionClient {
        let live = LiveTranscriptionClient.liveValue
        var client = live
        client.feed = { samples in
            await live.feed(samples)
            marks.fed.withValue { $0 += 1 }
        }
        client.finish = {
            await live.finish()
            marks.mark(.liveFinished)
        }
        return client
    }

    /// The real paste — preflight, snapshot, write, the 500 ms wait, the restore —
    /// on a pasteboard nobody else reads, and nothing posted.
    private static func pasteboard(_ marks: BenchMarks) -> PasteboardClient {
        let paster = PasteboardActor(board: boardName, post: { _ in marks.mark(.pasted) })
        return PasteboardClient(
            paste: { text, keep in
                marks.delivered.setValue(text)
                return await paster.paste(text, keepOnClipboard: keep)
            },
            copy: { await paster.copy($0) },
            undo: { await paster.undo() },
            frontmostApp: PasteboardClient.liveValue.frontmostApp
        )
    }

    private static func extensions(_ marks: BenchMarks) -> ExtensionClient {
        var client = ExtensionClient.liveValue
        client.deliver = { transcript, duration, app in
            ExtensionClient.liveValue.deliver(transcript, duration, app)
            marks.mark(.handoff)
        }
        return client
    }
}
