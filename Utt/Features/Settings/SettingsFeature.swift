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
        case resetToDefaultsTapped
    }

    private enum CancelID { case deviceWatch }

    @Dependency(\.audioDevices) var audioDevices
    @Dependency(\.transcription) var transcription
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
                return .none
            case let .hotkeyCaptured(hotkey):
                state.isRecordingHotkey = false
                $settings.withLock { $0.hotkey = hotkey }
                return .none
            case .hotkeyRecordingToggled:
                state.isRecordingHotkey.toggle()
                return .none
            case let .engineChanged(engine): return change(to: engine)
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
            while !Task.isCancelled {
                let devices = audioDevices.inputDevices()
                await send(.devicesLoaded(devices, defaultName: audioDevices.defaultInputDevice()?.name))
                try await clock.sleep(for: .seconds(3))
            }
        }
        .cancellable(id: CancelID.deviceWatch, cancelInFlight: true)
    }

    /// "Only start on double-tap" without the lock would mean "start on double-tap,
    /// never stop". `UttSettings` enforces this on decode; this enforces it on edit.
    func normalize() -> Effect<Action> {
        if !settings.doubleTapLockEnabled, settings.useDoubleTapOnly {
            $settings.withLock { $0.useDoubleTapOnly = false }
        }
        return .none
    }

    func change(to engine: TranscriptionEngine) -> Effect<Action> {
        guard engine != settings.transcriptionEngine else { return .none }
        $settings.withLock { $0.transcriptionEngine = engine }
        // Drop the old engine's weights before loading the new ones — both resident
        // at once is roughly a gigabyte for no benefit.
        return .run { _ in
            await transcription.unload()
            try? await transcription.prewarm(engine)
        }
    }
}
