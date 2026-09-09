import Foundation

/// One parsed HTTP/1.1 request. Header names arrive lowercased — a client that
/// sends `AUTHORIZATION` is not a client worth rejecting.
public struct HttpRequest: Equatable, Sendable {
    public let method: String
    /// Path only; any query string is already stripped.
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public enum HttpParseError: Error, Equatable {
    /// A well-formed start, but the rest of the request has not arrived yet.
    case incomplete
    case malformed
    /// Headers or body past the cap. The connection is closed rather than read on:
    /// this is the one path by which a stranger could make utt allocate memory.
    case tooLarge
}

/// A parser for exactly the requests this API serves, and nothing else. It is the
/// entire attack surface reachable before the token is checked, which is why it
/// lives here with tests rather than inline in the connection handler.
public enum HttpRequestParser {
    /// The request line plus every header. Anything larger is not a client we serve.
    public static let maximumHeaderBytes = 8 * 1024

    /// Parses one request out of everything received so far. Throws `.incomplete`
    /// while the caller should keep reading.
    public static func parse(_ buffer: Data, maximumBodyBytes: Int) throws -> HttpRequest {
        let separator = Data("\r\n\r\n".utf8)
        guard let blankLine = buffer.range(of: separator) else {
            throw buffer.count > maximumHeaderBytes ? HttpParseError.tooLarge : .incomplete
        }
        let headerBytes = buffer.distance(from: buffer.startIndex, to: blankLine.lowerBound)
        guard headerBytes <= maximumHeaderBytes else { throw HttpParseError.tooLarge }
        guard let head = String(data: buffer[buffer.startIndex..<blankLine.lowerBound], encoding: .utf8) else {
            throw HttpParseError.malformed
        }

        var lines = head.components(separatedBy: "\r\n")
        let (method, path) = try requestLine(lines.removeFirst())
        let headers = self.headers(from: lines)
        let length = try contentLength(headers, maximumBodyBytes: maximumBodyBytes)

        let bodyStart = blankLine.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else {
            throw HttpParseError.incomplete
        }
        let bodyEnd = buffer.index(bodyStart, offsetBy: length)
        return HttpRequest(method: method, path: path, headers: headers, body: Data(buffer[bodyStart..<bodyEnd]))
    }

    private static func requestLine(_ line: String) throws -> (method: String, path: String) {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { throw HttpParseError.malformed }
        // The query string is dropped rather than parsed: nothing this API does is
        // configurable per request, so a `?` is decoration.
        let path = String(fields[1].split(separator: "?", maxSplits: 1)[0])
        return (String(fields[0]).uppercased(), path)
    }

    private static func headers(from lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return headers
    }

    /// A missing length is an empty body; a length past the cap is refused before a
    /// single byte of it is read, not after.
    private static func contentLength(_ headers: [String: String], maximumBodyBytes: Int) throws -> Int {
        guard let raw = headers["content-length"] else { return 0 }
        guard let length = Int(raw), length >= 0 else { throw HttpParseError.malformed }
        guard length <= maximumBodyBytes else { throw HttpParseError.tooLarge }
        return length
    }
}

/// Responses are built whole and the connection is closed after each one. utt
/// serves a single clip per connection, which is all a recorder ever needs and
/// takes every keep-alive timeout out of the picture.
public enum HttpResponse {
    public static func json(status: Int, _ body: Data) -> Data {
        let head = "HTTP/1.1 \(status) \(reason(status))\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        var response = Data(head.utf8)
        response.append(body)
        return response
    }

    /// Errors carry a sentence, not a stack: the caller is a phone app, and
    /// anything more specific is a description of utt's internals.
    public static func error(status: Int, _ message: String) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data()
        return json(status: status, body)
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 413: "Payload Too Large"
        case 500: "Internal Server Error"
        default: "Error"
        }
    }
}
