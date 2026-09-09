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
        var defaultInputName: String?
        /// Set while the hotkey recorder is capturing the next chord.
        var isRecordingHotkey = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case devicesLoaded([AudioDevice], defaultName: String?)
        case hotkeyCaptured(HotKey)
        case hotkeyRecordingToggled
        case engineChanged(TranscriptionEngine)
        case modelChanged(String)
        case apiChanged(ApiSettings)
        case resetToDefaultsTapped
    }

    private enum CancelID { case deviceWatch }

    @Dependency(\.audioDevices) var audioDevices
    @Dependency(\.continuousClock) var clock
    @Shared(.uttSettings) var settings

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding: return normalize()
            case .task: return watchDevices()
            case let .devicesLoaded(devices, name):
                state.inputDevices = devices
                state.defaultInputName = name
                return rememberNames(from: devices)
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
            try JSONEncoder().encode(devices).write(to: URL.uttDevicesFile, options: .atomic)
        } catch {
            log.debug("could not export device list: \(error.localizedDescription)")
        }
    }

    /// A device can only be named while it is attached, which is never the moment
    /// the name is needed — so it is captured from every poll instead. This is also
    /// what gives names to UIDs that arrived without one: a list seeded from the
    /// legacy `selectedMicrophoneID`, or a device added from Raycast.
    ///
    /// Names for UIDs no longer in the list go with them, so the map cannot grow
    /// into a log of every microphone the machine has ever seen.
    func rememberNames(from devices: [AudioDevice]) -> Effect<Action> {
        let named = Dictionary(
            settings.microphonePriority.map { uid in
                (uid, devices.first { $0.id == uid }?.name ?? settings.microphoneNames[uid])
            }.compactMap { uid, name in name.map { (uid, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        guard named != settings.microphoneNames else { return .none }
        $settings.withLock { $0.microphoneNames = named }
        return .none
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
