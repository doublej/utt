import ComposableArchitecture
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "feature.app")

/// Root reducer: lifecycle, permissions, model readiness, and the single serialized
/// hotkey stream.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var transcription = TranscriptionFeature.State()
        var settings = SettingsFeature.State()
        var history = HistoryFeature.State()
        var model: ModelState = .idle
        var missingPermissions: [Permission] = []
        /// Seen missing on the most recent poll but not yet on two in a row. See
        /// `permissionsChecked`.
        var unconfirmedMissing: Set<Permission> = []
        /// True when a grant landed but this process still sees the old answer.
        var needsRelaunch = false
        /// False until an appcast is actually hosted — see `UpdaterClient`. The UI
        /// hides the update affordances rather than offering one that cannot work.
        var updatesConfigured = false
        /// Nil until the first-run check has run, so the UI does not flash a
        /// welcome screen at someone who has been using utt for a month.
        var isFirstRun: Bool?
    }

    /// There is no progress callback to hang a percentage on: FluidAudio's
    /// `downloadAndLoad` reports nothing until it returns, and the first load also
    /// pays a one-time ~27 s ANE compile. So this is deliberately indeterminate —
    /// a fake progress bar that stalls at 69% is worse than an honest spinner.
    enum ModelState: Equatable {
        case idle
        case preparing(since: Date)
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    enum Action {
        case task
        case permissionsChecked([Permission], needsRelaunch: Bool)
        case keyEventReceived(KeyEvent)
        case modelPrepared(Result<Bool, Never>)
        case prepareModelTapped
        case grantTapped(Permission)
        case relaunchTapped
        case firstRunChecked(Bool)
        /// ⌥⇧V, or the menu bar item — put the last transcript back where the
        /// cursor is now.
        case pasteLastTapped
        case copyLastTapped
        case checkForUpdatesTapped
        case transcription(TranscriptionFeature.Action)
        case settings(SettingsFeature.Action)
        case history(HistoryFeature.Action)
    }

    private enum CancelID { case keyEvents, permissionPoll, modelPrepare }

    @Dependency(\.keyEventMonitor) var keyEventMonitor
    @Dependency(\.recording) var recording
    @Dependency(\.appPresence) var appPresence
    @Dependency(\.updater) var updater
    @Dependency(\.permissions) var permissions
    @Dependency(\.transcription) var transcription
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Shared(.uttSettings) var settings
    @Shared(.uttHistory) var transcripts

    /// Lives here rather than in State because it is not `Equatable` state the UI
    /// should diff on — it is the accumulated position of a state machine.
    /// Fixed, not user-settable: it is a convenience, and every chord offered to
    /// the recorder is one more chance to shadow something the user already relies on.
    static let pasteLastHotKey = HotKey(key: .v, modifiers: [.option, .shift])

    private static let processor = LockIsolated(HotKeyProcessor(hotkey: .init(key: nil, modifiers: [])))
    private static let recorder = LockIsolated(HotKeyRecorder())

    var body: some ReducerOf<Self> {
        Scope(state: \.transcription, action: \.transcription) { TranscriptionFeature() }
        Scope(state: \.settings, action: \.settings) { SettingsFeature() }
        Scope(state: \.history, action: \.history) { HistoryFeature() }
        Reduce { state, action in
            switch action {
            case .task: return start(&state)
            case let .permissionsChecked(missing, relaunch): return permissionsChecked(&state, missing, relaunch)
            case let .keyEventReceived(event): return handle(event, &state)
            case let .modelPrepared(.success(loaded)):
                state.model = loaded ? .ready : .failed("Could not load the transcription model")
                return .none
            case .prepareModelTapped: return prepareModel(&state)
            case let .grantTapped(permission): return grant(permission)
            case .relaunchTapped: return .run { _ in permissions.relaunch() }
            case .pasteLastTapped: return withLastTranscript { _ = await pasteboard.paste($0) }
            case .copyLastTapped: return withLastTranscript { await pasteboard.copy($0) }
            case .checkForUpdatesTapped: return .run { _ in await updater.checkForUpdates() }
            case let .firstRunChecked(isFirst): state.isFirstRun = isFirst; return .none

            // Child-to-parent is plain pattern matching on the child action —
            // no delegate-action ceremony.
            case let .transcription(.pasteFinished(pasted)): return recordHistory(&state, pasted: pasted)

            // Every route by which the hotkey or its timings can change, since the
            // processor holding them is not in state and cannot observe them.
            case .settings(.binding), .settings(.hotkeyCaptured),
                 .settings(.resetToDefaultsTapped):
                return .merge(syncProcessor(), applySystemPreferences())

            case .settings(.hotkeyRecordingToggled):
                Self.recorder.setValue(HotKeyRecorder())
                return .none

            case .transcription, .settings, .history: return .none
            }
        }
    }
}

private extension AppFeature {
    func start(_ state: inout State) -> Effect<Action> {
        syncProcessorNow()
        state.updatesConfigured = updater.isConfigured()

        return .merge(
            // ONE stream, ONE consumer. Spawning a Task per event would let press
            // and release land out of order.
            .run { send in
                keyEventMonitor.start()
                for await event in keyEventMonitor.events() {
                    await send(.keyEventReceived(event))
                }
            }
            .cancellable(id: CancelID.keyEvents),

            .run { send in
                while !Task.isCancelled {
                    let missing = Permission.allCases.filter { permissions.status($0) != .granted }
                    await send(.permissionsChecked(missing, needsRelaunch: permissions.needsRelaunch()))
                    try await clock.sleep(for: .seconds(2))
                }
            }
            .cancellable(id: CancelID.permissionPoll),

            .send(.prepareModelTapped),
            .send(.settings(.task)),
            applySystemPreferences(),
            checkFirstRun()
        )
    }

    /// First run is "no settings file yet".
    func checkFirstRun() -> Effect<Action> {
        .run { send in
            let settingsExist = (try? URL.uttSettingsFile).map {
                FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
            } ?? false
            await send(.firstRunChecked(!settingsExist))
        }
    }

    func prepareModel(_ state: inout State) -> Effect<Action> {
        state.model = .preparing(since: now)
        return .run { [engine = settings.transcriptionEngine] send in
            try? await transcription.prewarm(engine)
            await send(.modelPrepared(.success(await transcription.isReady(engine))))
        }
        .cancellable(id: CancelID.modelPrepare, cancelInFlight: true)
    }

    /// A permission has to read as missing on **two consecutive polls** before the
    /// UI says so. `CGPreflightPostEventAccess` starts an asynchronous TCC lookup
    /// and answers "denied" until it lands, so a granted Accessibility permission
    /// reports missing for the first few milliseconds of every launch. Warming the
    /// call up front is not enough — the lookup is still in flight. Costing a real
    /// problem one extra poll to appear beats crying wolf at every launch.
    func permissionsChecked(
        _ state: inout State, _ missing: [Permission], _ relaunch: Bool
    ) -> Effect<Action> {
        let confirmed = missing.filter { state.unconfirmedMissing.contains($0) }
        state.unconfirmedMissing = Set(missing)

        let regained = !state.missingPermissions.isEmpty && confirmed.isEmpty
        if confirmed != state.missingPermissions {
            let names = confirmed.map(\.rawValue).joined(separator: ",")
            log.notice("permissions missing: \(names, privacy: .public)")
        }
        state.missingPermissions = confirmed
        state.needsRelaunch = relaunch

        // A tap created before Input Monitoring was granted stays dead forever;
        // tapEnable does nothing. Only a full recreate revives it.
        if regained, !keyEventMonitor.isRunning() {
            keyEventMonitor.start()
        }
        return .none
    }

    /// Try the system prompt first; fall back to System Settings when macOS has
    /// already spent this app's one prompt for that service.
    func grant(_ permission: Permission) -> Effect<Action> {
        .run { _ in
            if await !permissions.request(permission) {
                permissions.openSettings(permission)
            }
        }
    }

    /// While the settings panel is capturing a new chord, events go to the recorder
    /// instead of the processor — otherwise choosing a hotkey would also fire it.
    func handle(_ event: KeyEvent, _ state: inout State) -> Effect<Action> {
        guard !state.settings.isRecordingHotkey else {
            guard let captured = Self.recorder.withValue({ $0.process(event) }) else { return .none }
            Self.recorder.setValue(HotKeyRecorder())
            return .send(.settings(.hotkeyCaptured(captured)))
        }
        if matchesPasteLast(event) { return .send(.pasteLastTapped) }
        let output = Self.processor.withValue { $0.process(keyEvent: event) }
        guard let output else { return .none }
        return .send(.transcription(.hotKey(output)))
    }

    func matchesPasteLast(_ event: KeyEvent) -> Bool {
        event.key == Self.pasteLastHotKey.key
            && event.modifiers.erasingSides() == Self.pasteLastHotKey.modifiers
    }

    /// Falls back to history, so the shortcut still works in a session that has not
    /// recorded anything yet — which is every session right after a relaunch.
    func withLastTranscript(_ action: @escaping @Sendable (String) async -> Void) -> Effect<Action> {
        guard let text = transcripts.history.first?.text else { return .none }
        return .run { _ in await action(text) }
    }

    func recordHistory(_ state: inout State, pasted: Bool) -> Effect<Action> {
        guard let text = state.transcription.lastTranscript else { return .none }
        let duration = state.transcription.lastDuration
        return .run { send in
            // Nil when the paste failed: the text never reached an app, so claiming
            // one received it would be a lie in the history list.
            let app = pasted ? await pasteboard.frontmostApp() : nil
            await send(.history(.record(text: text, duration: duration, app: app)))
        }
    }

    /// Everything in settings that lives outside this process: the armed engine,
    /// the login item and the Dock icon. Pre-roll keeps the microphone open between
    /// recordings, so both its toggle and the device choice have to reach the
    /// recorder — a ring filled from the old microphone would prepend half a second
    /// of the wrong room.
    func applySystemPreferences() -> Effect<Action> {
        .run { [settings] _ in
            await recording.arm(settings.preRollEnabled, settings.selectedMicrophoneID, settings.keepMicrophoneWarm)
            await appPresence.setOpensAtLogin(settings.openOnLogin)
            await appPresence.setShowsDockIcon(settings.showDockIcon)
        }
    }

    /// The processor is not in state, so a settings edit has to be pushed into it.
    func syncProcessor() -> Effect<Action> {
        syncProcessorNow()
        return .none
    }

    func syncProcessorNow() {
        keyEventMonitor.setSuppressed([settings.hotkey, Self.pasteLastHotKey])
        Self.processor.withValue { processor in
            processor.hotkey = settings.hotkey
            processor.minimumKeyTime = settings.minimumKeyTime
            processor.doubleTapLockEnabled = settings.doubleTapLockEnabled
            processor.useDoubleTapOnly = settings.useDoubleTapOnly
        }
    }
}
