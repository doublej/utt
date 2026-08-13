import Testing
@testable import UttCore

@Suite("Model catalog")
struct ModelCatalogTests {
    @Test
    func everyModelIsListedUnderItsOwnEngine() {
        for engine in TranscriptionEngine.allCases {
            #expect(ModelCatalog.models(for: engine).allSatisfy { $0.engine == engine })
            #expect(!ModelCatalog.models(for: engine).isEmpty)
        }
    }

    @Test
    func identifiersAreUnique() {
        let ids = ModelCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// The whole reason `resolve` exists. A settings file can name a model from an
    /// older build; falling back beats an app that cannot transcribe until you edit
    /// JSON by hand.
    @Test
    func anUnknownIdFallsBackToTheRecommendation() {
        let resolved = ModelCatalog.resolve(id: "parakeet-tdt-0.6b-v3-coreml", engine: .parakeet)

        #expect(resolved == ModelCatalog.preferred(for: .parakeet))
    }

    /// Switching engine leaves the *other* engine's id in the setting until it is
    /// resolved. Whisper must never be handed a Parakeet bundle name.
    @Test
    func anIdFromTheOtherEngineDoesNotCrossOver() {
        let parakeetID = ModelCatalog.preferred(for: .parakeet).id

        let resolved = ModelCatalog.resolve(id: parakeetID, engine: .whisper)

        #expect(resolved.engine == .whisper)
        #expect(resolved == ModelCatalog.preferred(for: .whisper))
    }

    @Test
    func aKnownIdResolvesToItself() {
        for model in ModelCatalog.all {
            #expect(ModelCatalog.resolve(id: model.id, engine: model.engine) == model)
        }
    }

    /// Defaults have to survive a round trip through the settings file, and the
    /// default engine's recommendation is what a fresh install downloads.
    @Test
    func theDefaultSettingNamesARealModel() {
        let settings = UttSettings()

        let resolved = ModelCatalog.resolve(
            id: settings.selectedModel, engine: settings.transcriptionEngine
        )

        #expect(resolved.id == settings.selectedModel)
    }

    @Test
    func summaryStatesLanguagesAndSize() {
        let model = ModelCatalog.preferred(for: .parakeet)

        #expect(model.summary.contains(model.languages))
        #expect(model.summary.contains("MB"))
    }
}
