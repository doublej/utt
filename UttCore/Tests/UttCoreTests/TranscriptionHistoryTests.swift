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
