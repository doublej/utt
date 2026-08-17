import ComposableArchitecture
import Foundation
import UttCore

/// Everything the app knows about the weights: which model is on disk, which one
/// is in memory, and how far along the one in between has got.
extension AppFeature {
    /// Two phases, not one bar. The download knows its own fraction; the CoreML
    /// compile and load that follows reports nothing and takes a one-time ~27 s, so
    /// it gets a spinner and an elapsed time. A single percentage spanning both
    /// would be the bar that stalls at 69%.
    enum ModelState: Equatable {
        case idle
        case downloading(fraction: Double)
        case loading(since: Date)
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    /// Unloads first, unconditionally: every caller either has nothing loaded
    /// (launch) or wants what is loaded gone (engine change, model change, retry),
    /// and two engines' weights resident at once is roughly a gigabyte for nothing.
    /// The guard above it is what keeps re-picking the current model free.
    func prepareModel(_ state: inout State) -> Effect<Action> {
        let engine = settings.transcriptionEngine
        let model = ModelCatalog.resolve(id: settings.selectedModel, engine: engine).id
        let key = "\(engine)/\(model)"
        guard key != state.preparedKey || !state.model.isReady else { return .none }
        state.preparedKey = key
        // Named before the stream says anything, so the first frame on screen is
        // already truthful about which of the two phases this is going to be.
        state.model = transcription.isDownloaded(engine, model)
            ? .loading(since: now)
            : .downloading(fraction: 0)
        refreshDownloaded(&state)
        return .run { send in
            await transcription.unload()
            for await step in transcription.prepare(engine, model) {
                await send(.modelPreparation(step))
            }
            await send(.modelPrepared(.success(await transcription.isReady(engine, model))))
        }
        .cancellable(id: CancelID.modelPrepare, cancelInFlight: true)
    }

    /// The clock restarts when the phase does, so the elapsed time on screen is how
    /// long *this* phase has taken rather than how long ago the model was picked.
    func advance(_ state: inout State, to step: ModelPreparation) {
        switch step {
        case let .downloading(fraction):
            state.model = .downloading(fraction: fraction)
        case .loading:
            guard case .loading = state.model else {
                state.model = .loading(since: now)
                return
            }
        }
    }

    /// Eight `fileExists` calls, run when a download could have changed the answer.
    /// Cheaper than watching the two cache directories, and nothing else writes to
    /// them behind the app's back.
    func refreshDownloaded(_ state: inout State) {
        state.downloadedModels = Set(
            ModelCatalog.all
                .filter { transcription.isDownloaded($0.engine, $0.id) }
                .map(\.id)
        )
    }
}
