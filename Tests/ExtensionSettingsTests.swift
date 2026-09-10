import ComposableArchitecture
import Foundation
import Testing
import UttCore
@testable import utt

/// What reaches an extension's values file, and when.
///
/// The bug these pin down was found by running the real thing: opening an extension's
/// page drove the revision from 1 to 7 without anyone touching a control. SwiftUI
/// calls a binding's setter as the view settles, and every one of those calls was
/// a write — which is exactly the number an extension is watching to decide something
/// changed.
@MainActor
@Suite("Extension settings writes")
struct ExtensionSettingsTests {
    private let manifest = ExtensionManifest(
        id: "deckhand",
        name: "Deckhand",
        settings: [
            ExtensionSetting(key: "deliver", kind: .bool, label: "Deliver", value: .bool(true)),
            ExtensionSetting(key: "route", kind: .choice, label: "Route",
                          options: ["auto", "socket"], value: .string("auto"))
        ]
    )

    /// A recorder standing in for the values file.
    private final class Writes: @unchecked Sendable {
        var recorded: [(String, [String: ExtensionValue])] = []
    }

    private func makeStore(
        _ writes: Writes, consent: ExtensionConsent = .approved
    ) -> TestStore<SettingsFeature.State, SettingsFeature.Action> {
        let installed = InstalledExtension(manifest: manifest, values: [:], status: [:], consent: consent)
        return TestStore(initialState: SettingsFeature.State(extensions: [installed])) {
            SettingsFeature()
        } withDependencies: {
            $0.extensions = ExtensionClient(
                installed: { [installed] },
                write: { id, values, _ in writes.recorded.append((id, values)) },
                deliver: { _, _, _ in },
                request: { _, _ in },
                setEnabled: { _, _ in },
                setPriority: { _, _ in },
                remove: { _ in }
            )
        }
    }

    @Test("moving a control writes the whole set of values once")
    func writesOnRealChange() async {
        let writes = Writes()
        let store = makeStore(writes)
        await store.send(.extensionValueChanged("deckhand", key: "deliver", value: .bool(false))) {
            $0.extensions[0] = InstalledExtension(
                manifest: self.manifest,
                values: ["deliver": .bool(false), "route": .string("auto")],
                status: [:],
                consent: .approved
            )
        }
        #expect(writes.recorded.count == 1)
        #expect(writes.recorded[0].0 == "deckhand")
        // The whole set, not just the key that moved: the file is the store, and a
        // partial write would drop every other setting.
        #expect(writes.recorded[0].1 == ["deliver": .bool(false), "route": .string("auto")])
    }

    /// The churn the probe caught.
    @Test("a setter called with the value already showing writes nothing")
    func ignoresUnchangedValue() async {
        let writes = Writes()
        let store = makeStore(writes)
        await store.send(.extensionValueChanged("deckhand", key: "deliver", value: .bool(true)))
        #expect(writes.recorded.isEmpty)
    }

    /// An extension's page is a schema another process wrote; a value that does not fit
    /// the control must not reach the file.
    @Test("a value of the wrong kind is refused")
    func refusesMistypedValue() async {
        let writes = Writes()
        let store = makeStore(writes)
        await store.send(.extensionValueChanged("deckhand", key: "deliver", value: .string("yes")))
        await store.send(.extensionValueChanged("deckhand", key: "route", value: .string("carrier-pigeon")))
        await store.send(.extensionValueChanged("nobody", key: "deliver", value: .bool(false)))
        #expect(writes.recorded.isEmpty)
    }

    /// The person moving a band is a write like any other, and the guard against
    /// the setter firing as the view settles has to hold here too.
    @Test("choosing the band it already has writes nothing")
    func ignoresUnchangedPriority() async {
        let writes = Writes()
        let store = makeStore(writes)
        await store.send(.extensionPriorityChanged("deckhand", .normal))
    }

    /// The values file is the person's own choices, and for an extension that asked
    /// for one it carries the API token. Neither is written for something they have
    /// not ruled on — and this is the write path, so it is refused here rather than
    /// only hidden on the page.
    @Test("nothing is written for an extension nobody has approved")
    func refusesPendingExtension() async {
        let writes = Writes()
        let store = makeStore(writes, consent: .pending)
        await store.send(.extensionValueChanged("deckhand", key: "deliver", value: .bool(false)))
        #expect(writes.recorded.isEmpty)
    }
}

/// What an extension is handed when a transcript finishes.
///
/// The delivery point is `AppFeature`, not the history reducer: a person who turns
/// history off has said what utt should *keep*, not what an extension they installed
/// may be told.
@MainActor
@Suite("Extension transcript delivery")
struct ExtensionTranscriptTests {
    private struct Handed: Equatable {
        let text: String
        let raw: String
        let stages: [String]
        let duration: Double
        let app: String?
    }

    private final class Delivered: @unchecked Sendable {
        var received: [Handed] = []
    }

    private func makeStore(_ delivered: Delivered, keepHistory: Bool) -> TestStore<AppFeature.State, AppFeature.Action> {
        @Shared(.uttSettings) var settings
        $settings.withLock { $0.saveTranscriptionHistory = keepHistory }
        var state = AppFeature.State()
        state.transcription.lastTranscript = ProcessedTranscript(
            raw: "the words what were spoken",
            text: "the words that were spoken",
            stages: [.cleanup]
        )
        state.transcription.lastDuration = 3.4
        return TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.extensions = ExtensionClient(
                installed: { [] },
                write: { _, _, _ in },
                deliver: { transcript, duration, app in
                    delivered.received.append(Handed(
                        text: transcript.text,
                        raw: transcript.raw,
                        stages: transcript.stageNames,
                        duration: duration,
                        app: app
                    ))
                },
                request: { _, _ in },
                setEnabled: { _, _ in },
                setPriority: { _, _ in },
                remove: { _ in }
            )
            $0.pasteboard.frontmostApp = { AppIdentity(bundleID: "com.mitchellh.ghostty", name: "Ghostty") }
            $0.recording = .quiet
            $0.liveTranscription = .quiet
            $0.transcription = .quiet
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.keyEventMonitor.setSuppressed = { _ in }
        }
    }

    @Test("a finished transcript reaches the extensions with the app that received it")
    func deliversWithApp() async {
        let delivered = Delivered()
        let store = makeStore(delivered, keepHistory: true)
        store.exhaustivity = .off
        await store.send(.transcription(.pasteFinished(true)))
        await store.finish()
        #expect(delivered.received.count == 1)
        #expect(delivered.received.first?.text == "the words that were spoken")
        // Both versions and the stage that explains the difference — an extension
        // has no other way to tell a mishearing from something a stage took out.
        #expect(delivered.received.first?.raw == "the words what were spoken")
        #expect(delivered.received.first?.stages == ["cleanup"])
        #expect(delivered.received.first?.app == "Ghostty")
    }

    /// A failed paste reached no app, and saying it did would be a lie in both the
    /// history list and the extension's file.
    @Test("a transcript nothing received names no app")
    func deliversWithoutApp() async {
        let delivered = Delivered()
        let store = makeStore(delivered, keepHistory: true)
        store.exhaustivity = .off
        await store.send(.transcription(.pasteFinished(false)))
        await store.finish()
        #expect(delivered.received.first?.app == nil)
    }

    /// Retention is about what utt keeps, not about what an extension is told.
    @Test("history being off does not stop delivery")
    func deliversWithHistoryOff() async {
        let delivered = Delivered()
        let store = makeStore(delivered, keepHistory: false)
        store.exhaustivity = .off
        await store.send(.transcription(.pasteFinished(true)))
        await store.finish()
        #expect(delivered.received.count == 1)
    }
}
