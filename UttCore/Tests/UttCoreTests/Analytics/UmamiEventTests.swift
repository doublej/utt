import Foundation
import Testing
@testable import UttCore

/// The body Umami is sent, and the promise made about it on the settings page:
/// counts and choices, never what was said.
@Suite("Umami events")
struct UmamiEventTests {
    private func json(_ event: UmamiEvent, language: String = "en") throws -> [String: Any] {
        let data = try Umami.body(for: event, language: language)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("the body is the shape the collector expects")
    func bodyShape() throws {
        let body = try json(.launch(version: "2.1.0", engine: "parakeet", model: "tdt-v3"))

        #expect(body["type"] as? String == "event")
        let payload = try #require(body["payload"] as? [String: Any])
        #expect(payload["website"] as? String == Umami.websiteID)
        #expect(payload["hostname"] as? String == Umami.hostname)
        #expect(payload["name"] as? String == "launch")
        #expect(payload["url"] as? String == "/launch")
        #expect(payload["language"] as? String == "en")
        // A window size is a fingerprint, and there is no page to have come from.
        #expect(payload["screen"] as? String == "")
        #expect(payload["referrer"] as? String == "")
    }

    /// Seconds stay a number: a string would arrive in the dashboard as a label and
    /// could never be averaged.
    @Test("a dictation carries counts, not words")
    func dictationCarriesCounts() throws {
        let body = try json(
            .dictation(engine: "parakeet", model: "tdt-v3", seconds: 12, cleanup: false, delivered: true)
        )
        let payload = try #require(body["payload"] as? [String: Any])
        let data = try #require(payload["data"] as? [String: Any])

        #expect(data["seconds"] as? Int == 12)
        #expect(data["cleanup"] as? Bool == false)
        #expect(data["delivered"] as? Bool == true)
        #expect(data["engine"] as? String == "parakeet")
        #expect(Set(data.keys) == ["engine", "model", "seconds", "cleanup", "delivered"])
    }

    /// The two roads that are not a person at this Mac are distinguishable, and
    /// neither names who was asking.
    @Test("a backend job names its road and nothing else")
    func backendNamesTheRoad() throws {
        let api = try json(.backend(source: .api, engine: "parakeet", model: "tdt-v3"))
        let job = try json(.backend(source: .extensionJob, engine: "whisper", model: "large-v3"))

        #expect((api["payload"] as? [String: Any])?["url"] as? String == "/backend/api")
        #expect((job["payload"] as? [String: Any])?["url"] as? String == "/backend/extension")
        let data = try #require((job["payload"] as? [String: Any])?["data"] as? [String: Any])
        #expect(Set(data.keys) == ["source", "engine", "model"])
    }

    /// Umami refuses what it reads as a bot, which a bare `utt/2.1.0` is — and the
    /// version has to stay legible in what is sent instead.
    @Test("the user agent passes for a browser and still says which utt")
    func userAgentNamesTheVersion() {
        let agent = Umami.userAgent(version: "2.1.0")
        #expect(agent.hasPrefix("Mozilla/5.0 (Macintosh;"))
        #expect(agent.hasSuffix("utt/2.1.0"))
    }
}
