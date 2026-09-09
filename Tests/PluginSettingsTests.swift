import ComposableArchitecture
import Foundation
import Testing
import UttCore
@testable import utt

/// What reaches a plugin's values file, and when.
///
/// The bug these pin down was found by running the real thing: opening a plugin's
/// page drove the revision from 1 to 7 without anyone touching a control. SwiftUI
/// calls a binding's setter as the view settles, and every one of those calls was
/// a write — which is exactly the number a plugin is watching to decide something
/// changed.
@MainActor
@Suite("Plugin settings writes")
struct PluginSettingsTests {
    private let manifest = PluginManifest(
        id: "deckhand",
        name: "Deckhand",
        settings: [
            PluginSetting(key: "deliver", kind: .bool, label: "Deliver", value: .bool(true)),
            PluginSetting(key: "route", kind: .choice, label: "Route",
                          options: ["auto", "socket"], value: .string("auto"))
        ]
    )

    /// A recorder standing in for the values file.
    private final class Writes: @unchecked Sendable {
        var recorded: [(String, [String: PluginValue])] = []
    }

    private func makeStore(_ writes: Writes) -> TestStore<SettingsFeature.State, SettingsFeature.Action> {
        let installed = InstalledPlugin(manifest: manifest, values: [:], status: [:])
        return TestStore(initialState: SettingsFeature.State(plugins: [installed])) {
            SettingsFeature()
        } withDependencies: {
            $0.plugins = PluginClient(
                installed: { [installed] },
                write: { id, values, _ in writes.recorded.append((id, values)) },
                deliver: { _, _, _ in },
                request: { _, _ in }
            )
        }
    }

    @Test("moving a control writes the whole set of values once")
    func writesOnRealChange() async {
        let writes = Writes()
        let store = makeStore(writes)
        await store.send(.pluginValueChanged("deckhand", key: "deliver", value: .bool(false))) {
            $0.plugins[0] = InstalledPlugin(
                manifest: self.manifest,
                values: ["deliver": .bool(false), "route": .string("auto")],
                status: [:]
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
        await store.send(.pluginValueChanged("deckhand", key: "deliver", value: .bool(true)))
        #expect(writes.recorded.isEmpty)
    }

    /// A plugin's page is a schema another process wrote; a value that does not fit
    /// the control must not reach the file.
    @Test("a value of the wrong kind is refused")
    func refusesMistypedValue() async {
        let writes = Writes()
        let store = makeStore(writes)
        await store.send(.pluginValueChanged("deckhand", key: "deliver", value: .string("yes")))
        await store.send(.pluginValueChanged("deckhand", key: "route", value: .string("carrier-pigeon")))
        await store.send(.pluginValueChanged("nobody", key: "deliver", value: .bool(false)))
        #expect(writes.recorded.isEmpty)
    }
}

/// What a plugin is handed when a transcript finishes.
///
/// The delivery point is `AppFeature`, not the history reducer: a person who turns
/// history off has said what utt should *keep*, not what a plugin they installed
/// may be told.
@MainActor
@Suite("Plugin transcript delivery")
struct PluginTranscriptTests {
    private struct Handed: Equatable {
        let text: String
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
        state.transcription.lastTranscript = "the words that were spoken"
        state.transcription.lastDuration = 3.4
        return TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.plugins = PluginClient(
                installed: { [] },
                write: { _, _, _ in },
                deliver: { text, duration, app in
                    delivered.received.append(Handed(text: text, duration: duration, app: app))
                },
                request: { _, _ in }
            )
            $0.pasteboard.frontmostApp = { AppIdentity(bundleID: "com.mitchellh.ghostty", name: "Ghostty") }
            $0.recording = .quiet
            $0.transcription = .quiet
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.keyEventMonitor.setSuppressed = { _ in }
        }
    }

    @Test("a finished transcript reaches the plugins with the app that received it")
    func deliversWithApp() async {
        let delivered = Delivered()
        let store = makeStore(delivered, keepHistory: true)
        store.exhaustivity = .off
        await store.send(.transcription(.pasteFinished(true)))
        await store.finish()
        #expect(delivered.received.count == 1)
        #expect(delivered.received.first?.text == "the words that were spoken")
        #expect(delivered.received.first?.app == "Ghostty")
    }

    /// A failed paste reached no app, and saying it did would be a lie in both the
    /// history list and the plugin's file.
    @Test("a transcript nothing received names no app")
    func deliversWithoutApp() async {
        let delivered = Delivered()
        let store = makeStore(delivered, keepHistory: true)
        store.exhaustivity = .off
        await store.send(.transcription(.pasteFinished(false)))
        await store.finish()
        #expect(delivered.received.first?.app == nil)
    }

    /// Retention is about what utt keeps, not about what a plugin is told.
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
