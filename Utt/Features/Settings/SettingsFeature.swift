import ComposableArchitecture
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "feature.settings")

/// Settings are edited directly on `@Shared(.uttSettings)`, so there is no local
/// copy to keep in sync and no save button. This reducer exists for the parts that
/// are not a plain binding: enumerating microphones and switching engines.
@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var inputDevices: [AudioDevice] = []
        var extensions: [InstalledExtension] = []
        /// What launchd says about each extension's daemon, keyed by extension id. Read
        /// live rather than taken from the extension's own status file — a daemon that
        /// crashed leaves its last cheerful status behind.
        var daemonStates: [String: ExtensionDaemonState] = [:]
        /// What utt has done with extensions since it launched, newest first. Polled
        /// with them: the lanes that write it are actors and an audio-thread caller,
        /// and neither has a store to send to.
        var extensionLog: [ExtensionLogEntry] = []
        var defaultInputName: String?
        /// Set while the hotkey recorder is capturing the next chord.
        var isRecordingHotkey = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case devicesLoaded([AudioDevice], defaultName: String?)
        case extensionsLoaded([InstalledExtension])
        case extensionValueChanged(String, key: String, value: ExtensionValue)
        case extensionActionTapped(String, key: String)
        case extensionDaemonRestartTapped(String)
        case extensionEnabledChanged(String, Bool)
        case extensionPriorityChanged(String, ExtensionPriority)
        case extensionRemoveTapped(String)
        case extensionDaemonStateLoaded(String, ExtensionDaemonState)
        case extensionLogLoaded([ExtensionLogEntry])
        case hotkeyCaptured(HotKey)
        case hotkeyRecordingToggled
        case engineChanged(TranscriptionEngine)
        case modelChanged(String)
        case apiChanged(ApiSettings)
        case reconnectMicrophoneTapped(String)
        case resetToDefaultsTapped
    }

    /// Not private: the extension watch is cancelled from the other half of this
    /// reducer, in `SettingsFeature+Extensions.swift`.
    enum CancelID { case deviceWatch, extensionWatch }

    @Dependency(\.audioDevices) var audioDevices
    @Dependency(\.menuTracking) var menuTracking
    @Dependency(\.extensions) var extensions
    @Dependency(\.extensionDaemon) var extensionDaemon
    @Dependency(\.continuousClock) var clock
    @Shared(.uttSettings) var settings

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding: return normalize()
            case .task: return .merge(watchDevices(), watchExtensions())
            case let .devicesLoaded(devices, name):
                state.inputDevices = devices
                state.defaultInputName = name
                return remember(from: devices)
            case let .extensionsLoaded(installed):
                state.extensions = installed
                return .none
            case let .extensionValueChanged(id, key, value):
                return change(extension: id, key: key, to: value, in: &state)
            case let .extensionActionTapped(id, key):
                return .run { _ in extensions.request(id, key) }
            case let .extensionEnabledChanged(id, enabled):
                // Reloaded at once rather than at the next poll, so the switch
                // reads as having done something.
                guard state.extensions.first(where: { $0.id == id })?.enabled != enabled else { return .none }
                return .run { send in
                    extensions.setEnabled(id, enabled)
                    await send(.extensionsLoaded(extensions.installed()))
                }
            case let .extensionPriorityChanged(id, priority):
                // Reloaded at once, like the switch: the person moved a control and
                // the row has to show where it landed.
                guard state.extensions.first(where: { $0.id == id })?.priority != priority
                else { return .none }
                return .run { send in
                    extensions.setPriority(id, priority)
                    await send(.extensionsLoaded(extensions.installed()))
                }
            case let .extensionRemoveTapped(id):
                return .run { send in
                    extensions.remove(id)
                    await send(.extensionsLoaded(extensions.installed()))
                }
            case let .extensionDaemonRestartTapped(id):
                guard let label = state.extensions.first(where: { $0.id == id })?.manifest.daemon?.label
                else { return .none }
                // In the log because the question afterwards is always whether
                // restarting it helped, and that is unanswerable without knowing
                // when it was restarted.
                ExtensionLog.note(id, "you asked utt to restart its daemon")
                return .run { send in
                    await extensionDaemon.restart(label)
                    await send(.extensionDaemonStateLoaded(id, extensionDaemon.state(label)))
                }
            case let .extensionDaemonStateLoaded(id, daemonState):
                state.daemonStates[id] = daemonState
                return .none
            case let .extensionLogLoaded(entries):
                state.extensionLog = entries
                return .none
            case let .hotkeyCaptured(hotkey):
                state.isRecordingHotkey = false
                $settings.withLock { $0.hotkey = hotkey }
                return .none
            case .hotkeyRecordingToggled:
                state.isRecordingHotkey.toggle()
                return .none
            case let .engineChanged(engine): return change(to: engine)
            case let .modelChanged(model): return change(toModel: model)
            case let .apiChanged(api): return change(toApi: api)
            // Handled in `AppFeature` — reopening the input is the recorder's, and
            // nothing about it belongs in settings state.
            case .reconnectMicrophoneTapped: return .none
            case .resetToDefaultsTapped:
                $settings.withLock { $0 = UttSettings() }
                return .none
            }
        }
    }
}

private extension SettingsFeature {
    /// Devices come and go — a headset is plugged in mid-session and the picker has
    /// to notice. Polling beats a CoreAudio property listener here: the list is tiny
    /// and the listener would have to hop threads to reach the store anyway.
    func watchDevices() -> Effect<Action> {
        .run { send in
            var exported: [AudioDevice]?
            while !Task.isCancelled {
                let devices = audioDevices.inputDevices()
                await send(.devicesLoaded(devices, defaultName: audioDevices.defaultInputDevice()?.name))
                if devices != exported {
                    export(devices)
                    exported = devices
                }
                try await clock.sleep(for: .seconds(3))
            }
        }
        .cancellable(id: CancelID.deviceWatch, cancelInFlight: true)
    }

    /// Publishes the device list where processes that are not CoreAudio clients can
    /// read it — the Raycast extension picks microphones by UID, and a UID is not
    /// something `system_profiler` will tell it. Best-effort: a failed write only
    /// means Raycast shows a stale list.
    func export(_ devices: [AudioDevice]) {
        do {
            try JSONEncoder().encode(devices).writePrivately(to: URL.uttDevicesFile)
        } catch {
            log.debug("could not export device list: \(error.localizedDescription)")
        }
    }

    /// A device can only be named — or asked how it is attached — while it is
    /// plugged in, which is never the moment either answer is needed. So both are
    /// captured from every poll instead. This is also what gives names to UIDs that
    /// arrived without one: a list seeded from the legacy `selectedMicrophoneID`,
    /// or a device added from Raycast.
    ///
    /// Entries for UIDs no longer in the list go with them, so neither map can grow
    /// into a log of every microphone the machine has ever seen.
    func remember(from devices: [AudioDevice]) -> Effect<Action> {
        let named = remembered(devices, \.name, settings.microphoneNames)
        let sourced = remembered(devices, \.source.rawValue, settings.microphoneSources)
        guard named != settings.microphoneNames || sourced != settings.microphoneSources
        else { return .none }
        $settings.withLock {
            $0.microphoneNames = named
            $0.microphoneSources = sourced
        }
        return .none
    }

    /// One fact per listed UID: what the attached device says, or what was last
    /// recorded about it, or nothing.
    func remembered(
        _ devices: [AudioDevice],
        _ fact: KeyPath<AudioDevice, String>,
        _ previous: [String: String]
    ) -> [String: String] {
        Dictionary(
            settings.microphonePriority.map { uid in
                (uid, devices.first { $0.id == uid }?[keyPath: fact] ?? previous[uid])
            }.compactMap { uid, value in value.map { (uid, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// "Only start on double-tap" without the lock would mean "start on double-tap,
    /// never stop". `UttSettings` enforces this on decode; this enforces it on edit.
    func normalize() -> Effect<Action> {
        if !settings.doubleTapLockEnabled, settings.useDoubleTapOnly {
            $settings.withLock { $0.useDoubleTapOnly = false }
        }
        return .none
    }

    /// Storing the choice is all that happens here. Unloading the old weights and
    /// warming the new ones is `AppFeature`'s, because it owns the readiness the UI
    /// reads — see the `.settings(.engineChanged)` case there.
    func change(to engine: TranscriptionEngine) -> Effect<Action> {
        guard engine != settings.transcriptionEngine else { return .none }
        $settings.withLock { $0.transcriptionEngine = engine }
        // Each engine remembers its own model, so switching back and forth does not
        // silently reset the choice. An id belonging to the other engine resolves to
        // this one's recommendation.
        let model = ModelCatalog.resolve(id: settings.selectedModel, engine: engine).id
        $settings.withLock { $0.selectedModel = model }
        return .none
    }

    func change(toModel model: String) -> Effect<Action> {
        guard model != settings.selectedModel else { return .none }
        $settings.withLock { $0.selectedModel = model }
        return .none
    }

    /// The one write path for the API settings — the card cannot use a plain
    /// `@Shared` binding, because starting a listener is not something a file write
    /// reaches. The token is minted here on the first switch-on and then left alone:
    /// regenerating it behind the user's back would silently lock out every caller
    /// they had already set up.
    func change(toApi api: ApiSettings) -> Effect<Action> {
        var api = api
        if api.enabled, api.token.isEmpty { api.token = ApiToken.generate() }
        guard api != settings.api else { return .none }
        $settings.withLock { $0.api = api }
        return .none
    }
}
