import ComposableArchitecture
import Foundation
import UttCore

/// The settings that live outside this process, pushed out in one place. Its own
/// file because it is the only part of `AppFeature` that talks to four clients at
/// once, and because the closure it builds — the transcription an API caller and an
/// extension both get — is the app's second entry point, not a detail of the first.
extension AppFeature {
    /// Everything in settings that lives outside this process: the armed engine,
    /// the login item, the Dock icon and the API listener. Pre-roll keeps the
    /// microphone open between recordings, so both its toggle and the device choice
    /// have to reach the recorder — a ring filled from the old microphone would
    /// prepend half a second of the wrong room.
    func applySystemPreferences() -> Effect<Action> {
        .run { [settings, transcription, transcriptCleanup, clock, analytics] _ in
            // No panel on this road: a skipped reason travels in the transcript
            // itself, which is what an API caller and an extension read it off.
            let cleanup = transcriptCleanup.stage(enabled: settings.cleanupTranscripts)
            await recording.arm(
                settings.dictationEnabled && settings.preRollEnabled,
                settings.microphonePriority,
                settings.keepMicrophoneWarm
            )
            await appPresence.setOpensAtLogin(settings.openOnLogin)
            await appPresence.setShowsDockIcon(settings.showDockIcon)
            // A caller gets the same text the hotkey would have pasted: the engine
            // the settings name, then the user's own replacement and formatting
            // rules. An API that answered with the raw transcript would be a second
            // pipeline to keep in step with the first — and an extension dropping a file
            // is the same caller by another road, so it gets the same closure.
            let transcribe: @Sendable (URL, Set<TextStage>) async throws -> ProcessedTranscript = { url, skipping in
                let model = ModelCatalog.resolve(id: settings.selectedModel, engine: settings.transcriptionEngine).id
                var heard = HeardTranscript(text: "", words: [])
                let decoding = try await clock.measure {
                    heard = try await transcription.transcribe(url, settings.transcriptionEngine, model)
                }
                let piped = await settings.processTranscript(heard.text, skipping: skipping, cleanup: cleanup)
                return await extensionFilters.apply(piped.heard(heard.words).timed(.decode, decoding))
            }
            // The API skips nothing: a stranger over HTTP has no manifest to declare
            // one in, and the endpoint's promise is the text the hotkey would paste.
            let engine = settings.transcriptionEngine
            let model = ModelCatalog.resolve(id: settings.selectedModel, engine: engine).id
            await apiServer.apply(settings.api.configuration) { url in
                let transcript = try await transcribe(url, [])
                analytics.send(.backend(source: .api, engine: engine.rawValue, model: model))
                return transcript
            }
            await extensionJobs.apply { url, skipping in
                let transcript = try await transcribe(url, skipping)
                // Which road, never which extension: an installed extension names a
                // person's tools, and counting the road answers the question anyway.
                analytics.send(.backend(source: .extensionJob, engine: engine.rawValue, model: model))
                return transcript
            }
        }
    }

    /// Once per launch, which is what makes it a version count: how much of the
    /// installed base an update has reached is the one thing a released app cannot
    /// find out any other way.
    func trackLaunch() -> Effect<Action> {
        .run { [settings, analytics] _ in
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let engine = settings.transcriptionEngine
            analytics.send(
                .launch(
                    version: version,
                    engine: engine.rawValue,
                    model: ModelCatalog.resolve(id: settings.selectedModel, engine: engine).id
                )
            )
        }
    }
}
