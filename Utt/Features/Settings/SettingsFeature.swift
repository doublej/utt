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
        case extensionRemoveTapped(String)
        case extensionDaemonStateLoaded(String, ExtensionDaemonState)
        case hotkeyCaptured(HotKey)
        case hotkeyRecordingToggled
        case engineChanged(TranscriptionEngine)
        case modelChanged(String)
        case apiChanged(ApiSettings)
        case reconnectMicrophoneTapped(String)
        case resetToDefaultsTapped
    }

    private enum CancelID { case deviceWatch, extensionWatch }

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
            case let .extensionRemoveTapped(id):
                return .run { send in
                    extensions.remove(id)
                    await send(.extensionsLoaded(extensions.installed()))
                }
            case let .extensionDaemonRestartTapped(id):
                guard let label = state.extensions.first(where: { $0.id == id })?.manifest.daemon?.label
                else { return .none }
                return .run { send in
                    await extensionDaemon.restart(label)
                    await send(.extensionDaemonStateLoaded(id, extensionDaemon.state(label)))
                }
            case let .extensionDaemonStateLoaded(id, daemonState):
                state.daemonStates[id] = daemonState
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

    /// Extensions are files another process writes, so they appear and change without
    /// telling utt. The same 3 s cadence as the devices — an extension installed while
    /// the window is open shows up within one poll, and nothing needs FSEvents for
    /// a directory this small.
    ///
    /// Each poll also reconciles every values file: an extension that has just been
    /// installed gets one written from its own defaults, and one that declared
    /// `needsApi` picks up a token that was minted after it was installed.
    func watchExtensions() -> Effect<Action> {
        .run { send in
            while !Task.isCancelled {
                let installed = extensions.installed()
                for item in installed {
                    ExtensionStore.reconcile(item, api: apiAccess)
                }
                // An extension that is working rewrites its status file as it goes, and
                // utt's menu is built from that. SwiftUI rebuilds a `MenuBarExtra`
                // whenever the state behind it changes, and a rebuild under an open
                // menu closes the menu — so a poll that lands while one is open is
                // dropped and the next one three seconds later carries it. Files are
                // still reconciled: that is a write nobody is reading.
                if !menuTracking.isOpen() {
                    await send(.extensionsLoaded(installed))
                    for item in installed {
                        guard let label = item.manifest.daemon?.label else { continue }
                        await send(.extensionDaemonStateLoaded(item.id, extensionDaemon.state(label)))
                    }
                }
                try await clock.sleep(for: .seconds(3))
            }
        }
        .cancellable(id: CancelID.extensionWatch, cancelInFlight: true)
    }

    /// What an extension that asked for API access is given — nil while the API is off
    /// or has no token, so an extension never holds a credential for a listener that
    /// is not running.
    var apiAccess: ExtensionApiAccess? {
        guard settings.api.enabled, !settings.api.token.isEmpty else { return nil }
        return ExtensionApiAccess(token: settings.api.token, port: settings.api.port)
    }

    /// Writes the extension's values file immediately rather than at the next poll:
    /// something is watching that file, and a three-second lag between flicking a
    /// switch and the extension obeying it reads as a broken switch.
    func change(
        extension id: String, key: String, to value: ExtensionValue, in state: inout State
    ) -> Effect<Action> {
        guard let index = state.extensions.firstIndex(where: { $0.id == id }),
              let setting = state.extensions[index].settings.first(where: { $0.key == key }),
              setting.accepts(value),
              // SwiftUI calls a binding's setter as the view settles, not only when
              // a person moves the control. Writing on those would advance the
              // revision every time the page is looked at, and an extension watching
              // that number would act on a change nobody made.
              setting.value != value
        else { return .none }

        var values = state.extensions[index].settings
            .reduce(into: [String: ExtensionValue]()) { $0[$1.key] = $1.value }
        values[key] = value
        state.extensions[index] = InstalledExtension(
            manifest: state.extensions[index].manifest,
            values: values,
            status: state.extensions[index].status,
            enabled: state.extensions[index].enabled
        )
        let api = state.extensions[index].manifest.needsApi ? apiAccess : nil
        return .run { [values] _ in extensions.write(id, values, api) }
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
