//
//  ApiDocsTests.swift
//  UttCoreTests
//
//  The OpenAPI document is a hand-written string with escaped code samples in it,
//  which is exactly the kind of thing that goes silently wrong: a bad escape does
//  not fail to compile, it renders a blank reference page. So it is parsed here.
//

import Foundation
import Testing
@testable import UttCore

struct ApiDocsTests {
    private let server = "http://m2-2.local:8756"

    private func spec() throws -> [String: Any] {
        let raw = ApiDocs.openAPI(server: server, version: "9.9.9")
        let parsed = try JSONSerialization.jsonObject(with: Data(raw.utf8))
        return try #require(parsed as? [String: Any])
    }

    // MARK: - The document

    @Test("the document is valid JSON and names this install")
    func parsesAsJson() throws {
        let spec = try spec()
        #expect(spec["openapi"] as? String == "3.1.0")
        let info = try #require(spec["info"] as? [String: Any])
        #expect(info["version"] as? String == "9.9.9")
        let servers = try #require(spec["servers"] as? [[String: Any]])
        #expect(servers.first?["url"] as? String == server)
    }

    @Test("both endpoints are described")
    func describesEveryEndpoint() throws {
        let paths = try #require(try spec()["paths"] as? [String: Any])
        #expect(paths["/health"] != nil)
        #expect(paths["/transcribe"] != nil)
    }

    /// The escaped newlines and quotes in the code samples are the fragile part.
    /// If they survive the round trip, so does everything simpler.
    @Test("the code samples come back out as real code")
    func keepsTheCodeSamplesIntact() throws {
        let paths = try #require(try spec()["paths"] as? [String: Any])
        let post = try #require(
            (paths["/transcribe"] as? [String: Any])?["post"] as? [String: Any]
        )
        let samples = try #require(post["x-codeSamples"] as? [[String: Any]])
        #expect(samples.count == 3)
        let curl = try #require(samples.first?["source"] as? String)
        #expect(curl.contains("\n"))
        #expect(curl.contains("--data-binary @clip.wav"))
        #expect(!curl.contains("\\n"))
    }

    @Test("every response reference resolves to a component")
    func referencesResolve() throws {
        let spec = try spec()
        let components = try #require(spec["components"] as? [String: Any])
        let responses = try #require(components["responses"] as? [String: Any])
        let schemas = try #require(components["schemas"] as? [String: Any])
        for name in ["Unauthorized", "BadRequest", "TooLarge", "EngineFailed"] {
            #expect(responses[name] != nil, "missing response \(name)")
        }
        for name in ["Health", "Transcript", "Error"] {
            #expect(schemas[name] != nil, "missing schema \(name)")
        }
    }

    // MARK: - The page

    @Test("the page inlines the document so Redoc never needs the token")
    func inlinesTheDocument() {
        let page = ApiDocs.redocPage(server: server, version: "9.9.9")
        #expect(page.contains("Redoc.init("))
        #expect(page.contains("\"openapi\": \"3.1.0\""))
        #expect(!page.contains("spec-url"))
    }

    /// The token is in the address bar of this page. Without this the CDN is handed
    /// it in a Referer header on the very first request.
    @Test("the page tells the browser to send no referrer")
    func suppressesTheReferrer() {
        #expect(ApiDocs.redocPage(server: server, version: "1").contains(#"name="referrer" content="no-referrer""#))
    }

    // MARK: - The Host header

    @Test("a plausible host is used as it arrived")
    func keepsARealHost() {
        #expect(ApiDocs.server(host: "m2-2.local:8756", fallbackPort: 8756) == "http://m2-2.local:8756")
        #expect(ApiDocs.server(host: "192.168.1.5:9000", fallbackPort: 8756) == "http://192.168.1.5:9000")
        #expect(ApiDocs.server(host: "[::1]:8756", fallbackPort: 8756) == "http://[::1]:8756")
    }

    /// The header is written by whoever connected and is interpolated into a
    /// `<script>`. Anything that is not a host falls back to loopback rather than
    /// reaching the browser.
    @Test("a host that could break out of the page is refused")
    func refusesAnInjectedHost() {
        for host in ["</script><script>alert(1)</script>", "mac.local\" onload=\"x", "a b", "", nil] {
            #expect(ApiDocs.server(host: host, fallbackPort: 8756) == "http://127.0.0.1:8756", "\(host ?? "nil")")
        }
    }

    // MARK: - The guide

    @Test("the guide is filled in with this install's address")
    func fillsInTheBaseURL() {
        let guide = ApiGuide.markdown(baseURL: server)
        #expect(guide.contains("Base URL: `\(server)`"))
        #expect(guide.contains("\(server)/transcribe"))
        #expect(!guide.contains("{{base}}"))
    }

    /// A brief written to be pasted into a chat window must not carry the secret
    /// with it — the placeholder is the whole point.
    @Test("the guide leaves the token as a placeholder")
    func leavesTheTokenOut() {
        let guide = ApiGuide.markdown(baseURL: server)
        #expect(guide.contains("Authorization: Bearer <token>"))
        #expect(guide.contains("Keychain"))
    }

    @Test("the guide states the three things a client gets wrong")
    func namesTheGotchas() {
        let guide = ApiGuide.markdown(baseURL: server)
        #expect(guide.contains("Not multipart/form-data"))
        #expect(guide.contains("Connection: close"))
        #expect(guide.contains("16 kHz mono"))
    }
}
