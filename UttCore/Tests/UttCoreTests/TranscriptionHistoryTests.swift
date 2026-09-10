import Foundation
import Testing

@testable import UttCore

@Suite("TranscriptionHistory")
struct TranscriptionHistoryTests {
    private func entry(_ text: String) -> Transcript {
        Transcript(timestamp: Date(timeIntervalSince1970: 0), text: text, duration: 1)
    }

    @Test func newestEntryComesFirst() {
        var history = TranscriptionHistory()
        history.record(entry("first"), cap: nil)
        history.record(entry("second"), cap: nil)
        #expect(history.history.map(\.text) == ["second", "first"])
    }

    @Test func nilCapKeepsEverything() {
        var history = TranscriptionHistory()
        for index in 0..<50 { history.record(entry("\(index)"), cap: nil) }
        #expect(history.history.count == 50)
    }

    @Test func capTrimsTheOldest() {
        var history = TranscriptionHistory()
        for index in 0..<5 { history.record(entry("\(index)"), cap: 3) }
        #expect(history.history.map(\.text) == ["4", "3", "2"])
    }

    /// A cap of zero has to mean "keep nothing". Trimming to `count - cap` without
    /// this guard would leave the entry that was just inserted.
    @Test func zeroCapKeepsNothing() {
        var history = TranscriptionHistory()
        history.record(entry("gone"), cap: 0)
        #expect(history.history.isEmpty)
    }

    /// There is a real `history.json` on every machine that has ever run utt, and
    /// it was written before `raw` existed. A decode that throws on it is data loss.
    @Test("a history file written before `raw` existed still loads")
    func decodesAFileWithoutRaw() throws {
        let json = #"""
        {"history":[{"id":"8B3A8D08-9F4A-4E6E-9E5E-4C0B0C7C7A11",
        "timestamp":0,"text":"what was typed","duration":1.5,
        "sourceAppName":"Ghostty","sourceAppBundleID":"com.mitchellh.ghostty"}]}
        """#
        let decoder = JSONDecoder()
        let history = try decoder.decode(TranscriptionHistory.self, from: Data(json.utf8))
        let entry = try #require(history.history.first)
        #expect(entry.text == "what was typed")
        #expect(entry.raw == nil)
        #expect(entry.sourceAppName == "Ghostty")
    }

    @Test("what was heard survives a round trip")
    func keepsRawThroughARoundTrip() throws {
        var entry = entry("what was typed")
        entry.raw = "what was heard"
        let data = try JSONEncoder().encode(TranscriptionHistory(history: [entry]))
        let decoded = try JSONDecoder().decode(TranscriptionHistory.self, from: data)
        #expect(decoded.history.first?.raw == "what was heard")
    }

    @Test func removeDropsOnlyTheNamedEntry() {
        var history = TranscriptionHistory()
        let target = entry("target")
        history.record(entry("keep"), cap: nil)
        history.record(target, cap: nil)
        history.remove(target.id)
        #expect(history.history.map(\.text) == ["keep"])
    }

    @Test func transcriptsRoundTripThroughCodable() throws {
        var history = TranscriptionHistory()
        history.record(entry("hello"), cap: nil)
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(TranscriptionHistory.self, from: data) == history)
    }
}
