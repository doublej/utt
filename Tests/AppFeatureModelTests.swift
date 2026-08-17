import ComposableArchitecture
import Foundation
import Testing
@testable import utt

/// What the model card reads off. The bug this pins down is the one that made the
/// readout untrustworthy: a model change that never moved the state out of
/// `.ready`, so the UI claimed weights were loaded while they were downloading.
@MainActor
@Suite("AppFeature model readiness")
struct AppFeatureModelTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    private func makeStore(
        downloaded: Bool,
        steps: [ModelPreparation]
    ) -> TestStore<AppFeature.State, AppFeature.Action> {
        TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.transcription = TranscriptionClient(
                transcribe: { _, _, _ in "" },
                prepare: { _, _ in
                    AsyncStream { continuation in
                        for step in steps { continuation.yield(step) }
                        continuation.finish()
                    }
                },
                isDownloaded: { _, _ in downloaded },
                isReady: { _, _ in true },
                unload: {}
            )
            $0.date = .constant(Self.epoch)
        }
    }

    @Test("a model that is not on disk downloads before it loads")
    func phasesAreReportedInOrder() async {
        let store = makeStore(downloaded: false, steps: [.downloading(fraction: 0.5), .loading])
        store.exhaustivity = .off

        await store.send(.prepareModelTapped) { $0.model = .downloading(fraction: 0) }
        await store.receive(\.modelPreparation) { $0.model = .downloading(fraction: 0.5) }
        await store.receive(\.modelPreparation) { $0.model = .loading(since: Self.epoch) }
        await store.receive(\.modelPrepared) { $0.model = .ready }
        await store.finish()
    }

    @Test("a model already on disk skips straight to loading")
    func downloadedModelDoesNotClaimToDownload() async {
        let store = makeStore(downloaded: true, steps: [.loading])
        store.exhaustivity = .off

        await store.send(.prepareModelTapped) { $0.model = .loading(since: Self.epoch) }
        await store.receive(\.modelPrepared) { $0.model = .ready }
        await store.finish()
    }

    /// Preparing unloads first, so doing it to the model already in memory would
    /// cost the CoreML compile again for nothing.
    @Test("re-preparing the loaded model leaves it alone")
    func preparingTwiceIsANoOp() async {
        let store = makeStore(downloaded: true, steps: [.loading])
        store.exhaustivity = .off

        await store.send(.prepareModelTapped)
        await store.receive(\.modelPrepared) { $0.model = .ready }
        await store.send(.prepareModelTapped)
        #expect(store.state.model == .ready)
        await store.finish()
    }
}
