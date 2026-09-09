import Foundation
import UttCore
import os

private let log = Logger(subsystem: UttLog.subsystem, category: "api")

/// Two endpoints and a token. Split from `ApiServer` so what the API *is* reads
/// separately from how bytes reach it.
enum ApiRoutes {
    static func respond(
        to request: HttpRequest,
        configuration: ApiConfiguration,
        transcribe: @escaping ApiServer.Transcriber
    ) async -> Data {
        guard authorized(request, token: configuration.token) else {
            return HttpResponse.error(
                status: 401, "Send Authorization: Bearer <token>. The token is in utt's settings."
            )
        }
        switch (request.method, request.path) {
        case ("GET", "/health"): return health()
        case ("POST", "/transcribe"): return await transcribeClip(request, transcribe)
        default: return HttpResponse.error(status: 404, "Only GET /health and POST /transcribe exist.")
        }
    }

    /// Parse failures, answered before any routing and therefore before the token —
    /// they are the shape of the request, not its contents.
    static func failure(for error: Error) -> Data {
        guard let parseError = error as? HttpParseError, parseError == .tooLarge else {
            return HttpResponse.error(status: 400, "Not an HTTP request this API understands.")
        }
        let megabytes = ApiConfiguration.maximumBodyBytes / 1024 / 1024
        return HttpResponse.error(status: 413, "That clip is larger than \(megabytes) MB.")
    }

    /// Every endpoint, `/health` included. One that answers before the token is
    /// checked is one that tells a scanner what it found.
    private static func authorized(_ request: HttpRequest, token: String) -> Bool {
        guard let header = request.headers["authorization"] else { return false }
        let prefix = "bearer "
        let offered = header.lowercased().hasPrefix(prefix) ? String(header.dropFirst(prefix.count)) : header
        return ApiToken.matches(offered.trimmingCharacters(in: .whitespaces), token)
    }

    private static func health() -> Data {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let body = (try? JSONSerialization.data(withJSONObject: ["ok": true, "version": version])) ?? Data()
        return HttpResponse.json(status: 200, body)
    }

    /// The body is the audio, whole, with no multipart wrapper: a recorder has one
    /// file to send and parsing multipart would be more code than the rest of this
    /// server put together.
    private static func transcribeClip(
        _ request: HttpRequest, _ transcribe: ApiServer.Transcriber
    ) async -> Data {
        guard !request.body.isEmpty else {
            return HttpResponse.error(status: 400, "POST the audio bytes as the request body.")
        }
        let name = "utt-api-\(UUID().uuidString).\(fileExtension(request.headers["content-type"]))"
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try request.body.write(to: url, options: .atomic)
            let text = try await transcribe(url)
            let body = (try? JSONSerialization.data(withJSONObject: ["text": text])) ?? Data()
            return HttpResponse.json(status: 200, body)
        } catch {
            log.error("transcription failed: \(error.localizedDescription, privacy: .public)")
            return HttpResponse.error(status: 500, "Could not transcribe that clip.")
        }
    }

    /// AVFoundation picks its reader by file extension, so a wav handed over as
    /// `.m4a` fails to open however correct its bytes are. An unknown type is
    /// called wav, which is what a recorder that sends no Content-Type is sending.
    private static func fileExtension(_ contentType: String?) -> String {
        let type = contentType?.split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased()
        switch type {
        case "audio/mp4", "audio/m4a", "audio/x-m4a": return "m4a"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/aiff", "audio/x-aiff": return "aiff"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/caf", "audio/x-caf": return "caf"
        default: return "wav"
        }
    }
}
