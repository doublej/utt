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
        /// Catalog ids whose weights are on disk. Recomputed rather than observed:
        /// a model only appears or disappears because this reducer downloaded it.
        var downloadedModels: Set<String> = []
        /// Which engine and model the readout above describes, so re-picking what is
        /// already loaded does not unload it and pay the compile a second time.
        var preparedKey = ""
        /// What the API listener is doing, which is not what the settings ask for:
        /// a port already in use leaves the switch on and nothing listening.
        var apiState: ApiServerState = .off
        /// Set while a plugin's clip is being transcribed — the menu bar mark runs
        /// in that plugin's colour so work arriving from elsewhere is not mistaken
        /// for dictation at this Mac.
        var pluginActivity: PluginActivity?
    }

    enum Action {
        case task
        case permissionsChecked([Permission], needsRelaunch: Bool)
        case keyEventReceived(KeyEvent)
        case modelPreparation(ModelPreparation)
        case modelPrepared(Result<Bool, Never>)
        case apiStateChanged(ApiServerState)
        case pluginActivityChanged(PluginActivity?)
        case prepareModelTapped
        case grantTapped(Permission)
        case relaunchTapped
        /// ⌥⇧V, or the menu bar item — put the last transcript back where the
        /// cursor is now.
        case pasteLastTapped
        case copyLastTapped
        case checkForUpdatesTapped
        case transcription(TranscriptionFeature.Action)
        case settings(SettingsFeature.Action)
        case history(HistoryFeature.Action)
    }

    enum CancelID { case keyEvents, permissionPoll, modelPrepare, apiStates, pluginActivity }

    @Dependency(\.keyEventMonitor) var keyEventMonitor
    @Dependency(\.recording) var recording
    @Dependency(\.appPresence) var appPresence
    @Dependency(\.updater) var updater
    @Dependency(\.permissions) var permissions
    @Dependency(\.transcription) var transcription
    @Dependency(\.apiServer) var apiServer
    @Dependency(\.plugins) var plugins
    @Dependency(\.pluginJobs) var pluginJobs
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Shared(.uttSettings) var settings
    @Shared(.uttHistory) var transcripts

    var body: some ReducerOf<Self> {
        Scope(state: \.transcription, action: \.transcription) { TranscriptionFeature() }
        Scope(state: \.settings, action: \.settings) { SettingsFeature() }
        Scope(state: \.history, action: \.history) { HistoryFeature() }
        Reduce { state, action in
            switch action {
            case .task: return start(&state)
            case let .permissionsChecked(missing, relaunch): return permissionsChecked(&state, missing, relaunch)
            case let .keyEventReceived(event): return handle(event, &state)
            case let .modelPreparation(step):
                advance(&state, to: step)
                return .none
            case let .modelPrepared(.success(loaded)):
                let key = state.preparedKey
                log.notice("\(key, privacy: .public) \(loaded ? "ready" : "failed", privacy: .public)")
                state.model = loaded ? .ready : .failed("Could not load the model — try again")
                refreshDownloaded(&state)
                return .none
            case let .apiStateChanged(update):
                state.apiState = update
                return .none
            case let .pluginActivityChanged(activity):
                state.pluginActivity = activity
                return .none
            case .prepareModelTapped: return prepareModel(&state)
            case let .grantTapped(permission): return grant(permission)
            case .relaunchTapped: return .run { _ in permissions.relaunch() }
            case .pasteLastTapped:
                // ⌥⇧V is an explicit "put it back", so it pastes whatever the
                // delivery mode says — and honours the same clipboard preference.
                return withLastTranscript(state) { [settings] in
                    _ = await pasteboard.paste($0, settings.copyToClipboard)
                }
            case .copyLastTapped: return withLastTranscript(state) { await pasteboard.copy($0) }
            case .checkForUpdatesTapped: return .run { _ in await updater.checkForUpdates() }

            // Child-to-parent is plain pattern matching on the child action —
            // no delegate-action ceremony. Every transcription action lands here,
            // which is what makes it the single point where key suppression is
            // rederived: review arms and disarms inside that child.
            case let .transcription(child):
                applySuppression(state)
                guard case let .pasteFinished(pasted) = child else { return .none }
                return recordHistory(&state, pasted: pasted)

            // Every route by which the hotkey or its timings can change, since the
            // processor holding them is not in state and cannot observe them.
            case .settings(.binding), .settings(.hotkeyCaptured):
                return .merge(syncProcessor(state), applySystemPreferences())

            // Switching engine or model is switching weights, and the settings
            // reducer has already stored the new choice by the time this runs.
            // Preparing here rather than there is what keeps the status readout
            // honest — done in the child, the UI would still say "Ready" about a
            // model that is no longer loaded.
            // `applySystemPreferences` too, because the API server closes over the
            // engine and model it should transcribe with.
            case .settings(.engineChanged), .settings(.modelChanged):
                return .merge(prepareModel(&state), applySystemPreferences())

            case .settings(.apiChanged):
                return applySystemPreferences()

            case .settings(.resetToDefaultsTapped):
                return .merge(syncProcessor(state), applySystemPreferences(), prepareModel(&state))

            // The armed engine is holding a device that has quietly stopped
            // delivering audio; only a full reopen gets it back.
            case let .settings(.reconnectMicrophoneTapped(uid)):
                return .run { _ in
                    await recording.reconnect(uid)
                    log.notice("reopened \(uid, privacy: .public) on request")
                }

            case .settings(.hotkeyRecordingToggled):
                return resetRecorder()

            case .settings, .history: return .none
            }
        }
    }
}

private extension AppFeature {
    func start(_ state: inout State) -> Effect<Action> {
        syncProcessorNow(state)
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

            .run { send in
                for await update in apiServer.states() {
                    await send(.apiStateChanged(update))
                }
            }
            .cancellable(id: CancelID.apiStates),

            .run { send in
                for await update in pluginJobs.activity() {
                    await send(.pluginActivityChanged(update))
                }
            }
            .cancellable(id: CancelID.pluginActivity),

            .send(.prepareModelTapped),
            .send(.settings(.task)),
            applySystemPreferences(),
            // Starting the updater is what schedules the daily check; nothing else
            // touches it until the button is pressed.
            .run { _ in await updater.start() }
        )
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

    func recordHistory(_ state: inout State, pasted: Bool) -> Effect<Action> {
        guard let text = state.transcription.lastTranscript else { return .none }
        let duration = state.transcription.lastDuration
        return .run { send in
            // Nil when the paste failed: the text never reached an app, so claiming
            // one received it would be a lie in the history list.
            let app = pasted ? await pasteboard.frontmostApp() : nil
            await send(.history(.record(text: text, duration: duration, app: app)))
            // The same moment, to any plugin that asked for transcripts. Not routed
            // through the history reducer: retention governs what utt keeps, not
            // what a plugin the user installed is handed.
            plugins.deliver(text, duration, app?.name ?? nil)
        }
    }

    /// Everything in settings that lives outside this process: the armed engine,
    /// the login item, the Dock icon and the API listener. Pre-roll keeps the
    /// microphone open between recordings, so both its toggle and the device choice
    /// have to reach the recorder — a ring filled from the old microphone would
    /// prepend half a second of the wrong room.
    func applySystemPreferences() -> Effect<Action> {
        .run { [settings, transcription] _ in
            await recording.arm(settings.preRollEnabled, settings.microphonePriority, settings.keepMicrophoneWarm)
            await appPresence.setOpensAtLogin(settings.openOnLogin)
            await appPresence.setShowsDockIcon(settings.showDockIcon)
            // A caller gets the same text the hotkey would have pasted: the engine
            // the settings name, then the user's own replacement and formatting
            // rules. An API that answered with the raw transcript would be a second
            // pipeline to keep in step with the first — and a plugin dropping a file
            // is the same caller by another road, so it gets the same closure.
            let transcribe: @Sendable (URL) async throws -> String = { url in
                let model = ModelCatalog.resolve(id: settings.selectedModel, engine: settings.transcriptionEngine).id
                let text = try await transcription.transcribe(url, settings.transcriptionEngine, model)
                return settings.applyTextTransforms(to: text)
            }
            await apiServer.apply(settings.api.configuration, transcribe)
            await pluginJobs.apply(transcribe)
        }
    }

}
