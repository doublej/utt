//
//  HttpRequestTests.swift
//  UttCoreTests
//
//  This parser is everything a stranger can reach before the token is checked, so
//  the cases that matter are the malformed ones: a truncated request must ask for
//  more bytes rather than half-parse, and an oversized one must be refused before
//  it is read into memory.
//

import Foundation
import Testing
@testable import UttCore

struct HttpRequestTests {
    private let cap = 1024

    private func request(_ text: String, body: Data = Data()) -> Data {
        var data = Data(text.utf8)
        data.append(body)
        return data
    }

    // MARK: - Parsing

    @Test("a complete request yields its method, path, headers and body")
    func parsesACompleteRequest() throws {
        let audio = Data([0x52, 0x49, 0x46, 0x46])
        let head = "POST /transcribe HTTP/1.1\r\n"
            + "Host: mac.local\r\n"
            + "Content-Type: audio/wav\r\n"
            + "Content-Length: 4\r\n\r\n"
        let raw = request(head, body: audio)
        let parsed = try HttpRequestParser.parse(raw, maximumBodyBytes: cap)
        #expect(parsed.method == "POST")
        #expect(parsed.path == "/transcribe")
        #expect(parsed.headers["content-type"] == "audio/wav")
        #expect(parsed.body == audio)
    }

    /// Header names are matched, not echoed, so a client that shouts is still a
    /// client that gets served.
    @Test("header names are lowercased and values trimmed")
    func normalizesHeaders() throws {
        let raw = request("GET /health HTTP/1.1\r\nAUTHORIZATION:   Bearer abc\r\n\r\n")
        let parsed = try HttpRequestParser.parse(raw, maximumBodyBytes: cap)
        #expect(parsed.headers["authorization"] == "Bearer abc")
    }

    @Test("the query string leaves the path and lands in query")
    func splitsTheQueryString() throws {
        let raw = request("GET /docs?token=abc%20123&expand=1 HTTP/1.1\r\n\r\n")
        let parsed = try HttpRequestParser.parse(raw, maximumBodyBytes: cap)
        #expect(parsed.path == "/docs")
        #expect(parsed.query["token"] == "abc 123")
        #expect(parsed.query["expand"] == "1")
    }

    /// The docs link carries the token in the query, so a second `token=` appended
    /// to it must not be the one that gets checked.
    @Test("a repeated query name keeps its first value")
    func firstQueryValueWins() throws {
        let raw = request("GET /docs?token=real&token=forged HTTP/1.1\r\n\r\n")
        #expect(try HttpRequestParser.parse(raw, maximumBodyBytes: cap).query["token"] == "real")
    }

    @Test("no query string is an empty query, not a missing path")
    func handlesAMissingQuery() throws {
        let parsed = try HttpRequestParser.parse(request("GET /health HTTP/1.1\r\n\r\n"), maximumBodyBytes: cap)
        #expect(parsed.path == "/health")
        #expect(parsed.query.isEmpty)
    }

    @Test("no content-length means an empty body")
    func treatsAMissingLengthAsEmpty() throws {
        let raw = request("GET /health HTTP/1.1\r\n\r\n")
        #expect(try HttpRequestParser.parse(raw, maximumBodyBytes: cap).body.isEmpty)
    }

    // MARK: - Framing

    @Test("headers that have not arrived yet ask for more bytes")
    func incompleteHeadersAreIncomplete() {
        #expect(throws: HttpParseError.incomplete) {
            try HttpRequestParser.parse(request("POST /transcribe HTTP/1.1\r\nHost: mac"), maximumBodyBytes: cap)
        }
    }

    /// The body arrives in TCP-sized pieces, and a request parsed off the first one
    /// would transcribe a truncated clip.
    @Test("a body still in flight asks for more bytes")
    func shortBodyIsIncomplete() {
        let raw = request("POST /transcribe HTTP/1.1\r\nContent-Length: 8\r\n\r\n", body: Data([1, 2, 3]))
        #expect(throws: HttpParseError.incomplete) {
            try HttpRequestParser.parse(raw, maximumBodyBytes: cap)
        }
    }

    @Test("anything past the body length is left alone")
    func stopsAtTheDeclaredLength() throws {
        let raw = request("POST /transcribe HTTP/1.1\r\nContent-Length: 2\r\n\r\n", body: Data([1, 2, 3, 4]))
        #expect(try HttpRequestParser.parse(raw, maximumBodyBytes: cap).body == Data([1, 2]))
    }

    // MARK: - Refusals

    @Test("a declared body past the cap is refused before it is read")
    func refusesAnOversizedBody() {
        let raw = request("POST /transcribe HTTP/1.1\r\nContent-Length: 99999\r\n\r\n")
        #expect(throws: HttpParseError.tooLarge) {
            try HttpRequestParser.parse(raw, maximumBodyBytes: cap)
        }
    }

    /// Without this a caller could hold a connection open sending header bytes for
    /// as long as it liked, and the buffer would grow for exactly as long.
    @Test("headers that never end are refused rather than buffered forever")
    func refusesEndlessHeaders() {
        let raw = request("GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: 9000))
        #expect(throws: HttpParseError.tooLarge) {
            try HttpRequestParser.parse(raw, maximumBodyBytes: cap)
        }
    }

    @Test("a request line with no path is malformed, not empty")
    func refusesAMalformedRequestLine() {
        #expect(throws: HttpParseError.malformed) {
            try HttpRequestParser.parse(request("GARBAGE\r\n\r\n"), maximumBodyBytes: cap)
        }
    }

    @Test("a content-length that is not a number is malformed")
    func refusesANonNumericLength() {
        #expect(throws: HttpParseError.malformed) {
            try HttpRequestParser.parse(
                request("POST /transcribe HTTP/1.1\r\nContent-Length: soon\r\n\r\n"),
                maximumBodyBytes: cap
            )
        }
    }

    // MARK: - Responses

    @Test("a response carries its own length and closes the connection")
    func buildsAWellFormedResponse() throws {
        let body = Data(#"{"text":"hello"}"#.utf8)
        let response = try #require(String(data: HttpResponse.json(status: 200, body), encoding: .utf8))
        #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(response.contains("Content-Length: \(body.count)\r\n"))
        #expect(response.contains("Connection: close\r\n"))
        #expect(response.hasSuffix("\r\n\r\n" + #"{"text":"hello"}"#))
    }

    @Test("an html response says so in its content type")
    func buildsAnHtmlResponse() throws {
        let page = try #require(String(data: HttpResponse.html(status: 200, "<p>hi</p>"), encoding: .utf8))
        #expect(page.contains("Content-Type: text/html; charset=utf-8\r\n"))
        #expect(page.hasSuffix("<p>hi</p>"))
    }

    @Test("an error response is json a client can read")
    func buildsAReadableError() throws {
        let data = HttpResponse.error(status: 401, "no token")
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(text.hasSuffix(#"{"error":"no token"}"#))
    }
}
