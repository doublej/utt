import Dependencies
import DependenciesMacros
import Foundation
import UttCore

/// Start, restart or stop the transcription API.
///
/// One entry point on purpose: the caller states the configuration it wants running
/// and the server works out the difference. A `start`/`stop` pair would need every
/// call site to know which one applies, and the call site is a settings edit that
/// only knows what the settings now say.
@DependencyClient
struct ApiServerClient: Sendable {
    /// `nil` stops the server. `transcribe` is re-supplied every time because it
    /// closes over the engine and model the settings currently name.
    var apply: @Sendable (
        _ configuration: ApiConfiguration?,
        _ transcribe: @escaping @Sendable (URL) async throws -> String
    ) async -> Void

    /// What the listener is actually doing. A stream rather than a return value
    /// because `NWListener` reports a failed bind asynchronously, long after the
    /// call that started it came back.
    var states: @Sendable () -> AsyncStream<ApiServerState> = { .finished }
}

extension ApiServerClient: DependencyKey {
    static let liveValue: ApiServerClient = {
        let server = ApiServer()
        return ApiServerClient(
            apply: { configuration, transcribe in
                await server.apply(configuration, transcribe: transcribe)
            },
            states: { server.states() }
        )
    }()
}

extension DependencyValues {
    var apiServer: ApiServerClient {
        get { self[ApiServerClient.self] }
        set { self[ApiServerClient.self] = newValue }
    }
}
