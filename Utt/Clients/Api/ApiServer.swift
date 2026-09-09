import Foundation
import Network
import UttCore
import os

private let log = Logger(subsystem: UttLog.subsystem, category: "api")

/// The transcription API: an HTTP/1.1 listener that takes a clip and answers with
/// its transcript, so a phone or a script can use the same on-device engine the
/// hotkey does.
///
/// Deliberately not a web server. No keep-alive, no routing table, no content
/// negotiation — everything reachable before the token is checked is attack
/// surface, and what is left of it is `HttpRequestParser` and `ApiAccess`, both in
/// `UttCore` with tests.
actor ApiServer {
    typealias Transcriber = @Sendable (URL) async throws -> String

    /// Network.framework delivers on this queue; nothing else runs on it.
    private let queue = DispatchQueue(label: "\(UttLog.subsystem).api")
    private var listener: NWListener?
    private var configuration: ApiConfiguration?
    /// Carries the engine and model choice, so it is replaced on every apply.
    private var transcribe: Transcriber?
    /// Held so an in-flight connection is not deallocated mid-request.
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// The request each connection is busy with, so tearing the listener down does
    /// not leave a transcription running that will answer into a scope the user has
    /// just narrowed. Cancelling cannot interrupt a decode already inside the
    /// engine; it does stop the reply and release the connection.
    private var work: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var observers: [UUID: AsyncStream<ApiServerState>.Continuation] = [:]
    private var state: ApiServerState = .off

    /// What the listener is actually doing, which is not what the settings say: a
    /// port already in use leaves the settings on and nothing listening.
    nonisolated func states() -> AsyncStream<ApiServerState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.observe(id, continuation) }
            continuation.onTermination = { _ in Task { await self.stopObserving(id) } }
        }
    }

    /// Idempotent in the configuration: every settings edit re-applies this, and
    /// restarting the listener each time would drop a request in flight because the
    /// user toggled an unrelated checkbox. The transcriber is refreshed regardless —
    /// it carries the engine and model choice, which is what may have changed.
    func apply(_ configuration: ApiConfiguration?, transcribe: @escaping Transcriber) {
        self.transcribe = transcribe
        guard configuration != self.configuration else { return }
        stop()
        guard let configuration else { return }
        start(configuration)
    }

    func stop() {
        teardown()
        report(.off)
    }

    private func start(_ configuration: ApiConfiguration) {
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // "This Mac only" binds to loopback rather than binding wide and refusing
        // afterwards: the port then never appears on a network interface, so there
        // is nothing for a scanner to find and no firewall prompt to approve. The
        // peer filter in `accept` still runs — two independent answers to the same
        // question, and the narrower one is enforced by the kernel.
        if configuration.access == .thisMac {
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        }
        do {
            let listener = configuration.access == .thisMac
                ? try NWListener(using: parameters)
                : try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] update in
                Task { await self?.listenerChanged(to: update) }
            }
            listener.start(queue: queue)
            self.listener = listener
            // Recorded now, not on `.ready`: a second apply while the listener is
            // still coming up must match and do nothing, rather than start a second.
            self.configuration = configuration
        } catch {
            log.error("could not listen on \(configuration.port): \(error.localizedDescription, privacy: .public)")
            report(.failed(Self.explain(error)))
        }
    }

    /// `.failed` is documented as terminal — the listener never recovers. Dropping
    /// the stored configuration with it is the load-bearing part: without that, the
    /// next apply sees the same settings, matches, and does nothing, so the port
    /// stays dead until the app is relaunched while the settings still read "on".
    private func listenerChanged(to update: NWListener.State) {
        switch update {
        case .ready:
            guard let configuration else { return }
            log.notice("listening on \(configuration.port) for \(configuration.access.rawValue, privacy: .public)")
            report(.listening(port: configuration.port))
        case let .failed(error):
            log.error("listener failed: \(error.localizedDescription, privacy: .public)")
            let reason = Self.explain(error)
            teardown()
            report(.failed(reason))
        default:
            break
        }
    }

    private func teardown() {
        // Cleared first: cancelling with the handler still attached calls straight
        // back in for the `.cancelled` transition.
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        configuration = nil
        for task in work.values { task.cancel() }
        work.removeAll()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard let configuration, let transcribe else {
            connection.cancel()
            return
        }
        let peer = Self.peer(of: connection)
        guard configuration.access.allows(peer: peer, localPrefixes: LocalInterfaces.prefixes()) else {
            log.notice("refused \(peer, privacy: .public), outside \(configuration.access.rawValue, privacy: .public)")
            connection.cancel()
            return
        }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        receive(connection, buffer: Data(), configuration: configuration, transcribe: transcribe)
    }

    private func receive(
        _ connection: NWConnection,
        buffer: Data,
        configuration: ApiConfiguration,
        transcribe: @escaping Transcriber
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            let ended = isComplete || error != nil
            Task {
                await self?.received(
                    connection, buffer: buffer, ended: ended,
                    configuration: configuration, transcribe: transcribe
                )
            }
        }
    }

    private func received(
        _ connection: NWConnection,
        buffer: Data,
        ended: Bool,
        configuration: ApiConfiguration,
        transcribe: @escaping Transcriber
    ) {
        do {
            let request = try HttpRequestParser.parse(
                buffer, maximumBodyBytes: ApiConfiguration.maximumBodyBytes
            )
            // Off the actor: transcribing takes seconds, and holding the actor for
            // them would stall every other connection behind this one.
            work[ObjectIdentifier(connection)] = Task { [weak self] in
                let response = await ApiRoutes.respond(
                    to: request, configuration: configuration, transcribe: transcribe
                )
                guard !Task.isCancelled else { return }
                await self?.send(response, over: connection)
            }
        } catch HttpParseError.incomplete where !ended {
            receive(connection, buffer: buffer, configuration: configuration, transcribe: transcribe)
        } catch {
            send(ApiRoutes.failure(for: error), over: connection)
        }
    }

    /// The send completion holds the connection, so dropping it from the registry
    /// here cannot deallocate it before the bytes are out.
    private func send(_ response: Data, over connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections.removeValue(forKey: id)
        work.removeValue(forKey: id)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func observe(_ id: UUID, _ continuation: AsyncStream<ApiServerState>.Continuation) {
        observers[id] = continuation
        continuation.yield(state)
    }

    private func stopObserving(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func report(_ update: ApiServerState) {
        guard update != state else { return }
        state = update
        for continuation in observers.values { continuation.yield(update) }
    }

    /// The one failure worth naming: the settings offer a port, and "already in use"
    /// is the answer the user can act on.
    private static func explain(_ error: Error) -> String {
        guard case let .posix(code)? = error as? NWError, code == .EADDRINUSE else {
            return error.localizedDescription
        }
        return "That port is already in use by another program."
    }

    /// The remote address of an inbound connection. An answer this cannot read comes
    /// back empty, which every scope but `.anywhere` refuses.
    private static func peer(of connection: NWConnection) -> String {
        guard case let .hostPort(host, _) = connection.endpoint else { return "" }
        switch host {
        case let .ipv4(address): return "\(address)"
        case let .ipv6(address): return "\(address)"
        case let .name(name, _): return name
        @unknown default: return ""
        }
    }
}
