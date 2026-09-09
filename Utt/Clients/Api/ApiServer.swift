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

    /// Idempotent in the configuration: every settings edit re-applies this, and
    /// restarting the listener each time would drop a request in flight because the
    /// user toggled an unrelated checkbox. The transcriber is refreshed regardless —
    /// it carries the engine and model choice, which is exactly what may have changed.
    func apply(_ configuration: ApiConfiguration?, transcribe: @escaping Transcriber) {
        self.transcribe = transcribe
        guard configuration != self.configuration else { return }
        stop()
        guard let configuration else { return }
        start(configuration)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        configuration = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
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
            listener.stateUpdateHandler = { state in
                guard case let .failed(error) = state else { return }
                log.error("listener failed: \(error.localizedDescription, privacy: .public)")
            }
            listener.start(queue: queue)
            self.listener = listener
            self.configuration = configuration
            log.notice("listening on \(configuration.port) for \(configuration.access.rawValue, privacy: .public)")
        } catch {
            log.error("could not listen on \(configuration.port): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func accept(_ connection: NWConnection) {
        guard let configuration, let transcribe else {
            connection.cancel()
            return
        }
        let peer = Self.peer(of: connection)
        guard configuration.access.allows(peer: peer) else {
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
            Task { [weak self] in
                let response = await ApiRoutes.respond(
                    to: request, configuration: configuration, transcribe: transcribe
                )
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
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
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
