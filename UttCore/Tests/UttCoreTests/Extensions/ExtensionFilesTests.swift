//
//  ExtensionFilesTests.swift
//  UttCoreTests
//
//  The bookkeeping around an extension rather than its manifest: which files are
//  its own, what the person decided, what utt wrote down about it, and what
//  launchctl says about its daemon.
//

import Foundation
import Testing
@testable import UttCore

struct ExtensionFilesTests {
    @Test("removal takes exactly the extension's own files")
    func ownsItsFiles() {
        // `deck.consent.json` above all: a consent record left behind by a removal
        // would approve the next install of the same id without anyone being asked.
        for name in ["deck.json", "deck.values.json", "deck.status.json", "deck.action.json",
                     "deck.transcript.json", "deck.partial.json", "deck.consent.json",
                     "deck.jobs", "deck.filter", "deck.disabled"] {
            #expect(ExtensionManifest.file(name, belongsTo: "deck"), "\(name)")
        }
        // Another extension whose id merely starts the same way, and ids with dots.
        #expect(!ExtensionManifest.file("deck.hand.json", belongsTo: "deck"))
        #expect(!ExtensionManifest.file("deckhand.json", belongsTo: "deck"))
        #expect(ExtensionManifest.file("deck.hand.json", belongsTo: "deck.hand"))
        #expect(!ExtensionManifest.file("deck.notes", belongsTo: "deck"))
        #expect(!ExtensionManifest.file("deck", belongsTo: "deck"))
    }
}

/// Consent is the one file utt reads where falling back to something workable is
/// the wrong answer: a record it cannot read must not grant anything.
struct ExtensionConsentTests {
    private func decode(_ json: String) throws -> ExtensionConsent {
        try JSONDecoder().decode(ExtensionConsentFile.self, from: Data(json.utf8)).decision
    }

    @Test("a decision utt wrote is read back as it was written")
    func roundTrips() throws {
        for decision in [ExtensionConsent.approved, .disabled] {
            let data = try JSONEncoder().encode(ExtensionConsentFile(
                decision: decision, decidedAt: "2026-09-10T14:22:07Z", priority: .last
            ))
            let read = try JSONDecoder().decode(ExtensionConsentFile.self, from: data)
            #expect(read.decision == decision)
            #expect(read.decidedAt == "2026-09-10T14:22:07Z")
            #expect(read.priority == .last)
        }
    }

    /// The two keys share a file, so neither may take the other down with it.
    @Test("an unreadable priority leaves the decision standing, and the other way round")
    func keysDecodeIndependently() throws {
        let file = try JSONDecoder().decode(
            ExtensionConsentFile.self,
            from: Data(#"{"decision": "approved", "priority": "urgent"}"#.utf8)
        )
        #expect(file.decision == .approved)
        #expect(file.priority == .normal)
        let other = try JSONDecoder().decode(
            ExtensionConsentFile.self,
            from: Data(#"{"decision": 7, "priority": "next"}"#.utf8)
        )
        #expect(other.decision == .pending)
        #expect(other.priority == .next)
    }

    /// The order the queue is taken in. `next` before `normal` before `last`, and
    /// the numbers themselves are nobody's business but the sort's.
    @Test("the bands rank in the order the person reads them in")
    func ranksInOrder() {
        #expect(ExtensionPriority.next.rank < ExtensionPriority.normal.rank)
        #expect(ExtensionPriority.normal.rank < ExtensionPriority.last.rank)
        #expect(Set(ExtensionPriority.allCases.map(\.rank)).count == ExtensionPriority.allCases.count)
    }

    /// Every one of these is a record nobody made: a truncated write, a hand-edit,
    /// or an extension trying to approve itself with a word utt does not know.
    @Test("a record utt cannot read grants nothing")
    func failsClosed() throws {
        #expect(try decode(#"{"decidedAt": "2026-09-10T14:22:07Z"}"#) == .pending)
        #expect(try decode(#"{"decision": "yes"}"#) == .pending)
        #expect(try decode(#"{"decision": true}"#) == .pending)
        #expect(try decode("{}") == .pending)
        // `pending` is the absence of a file, so a file claiming it is not consent
        // either — and reading it as one would be the same failure spelled out.
        #expect(try decode(#"{"decision": "pending"}"#) == .pending)
    }
}

/// The log is what an extension author has instead of `log stream`, so the two
/// things that would make it useless are what is tested: a repeated line burying
/// everything else, and a standing problem scrolling off the end.
struct ExtensionLogTests {
    private let moment = Date(timeIntervalSince1970: 1_789_052_649)

    private func entry(_ id: String?, _ message: String, at offset: TimeInterval = 0) -> ExtensionLogEntry {
        ExtensionLogEntry(
            extensionID: id, level: .problem, message: message,
            timestamp: moment.addingTimeInterval(offset)
        )
    }

    @Test("the same line said again is one entry, counted, with the latest time")
    func collapsesRepeats() {
        var book = ExtensionLogBook()
        let first = book.record(entry("deck", "no reply within 2 seconds"))
        // The line another extension is saying in between: manifests are re-read
        // three times a second, so repeats are never consecutive in practice, and a
        // rule that only looked at the newest entry would collapse nothing at all.
        let other = book.record(entry("hand", "setting refused — route"))
        let again = book.record(entry("deck", "no reply within 2 seconds", at: 60))
        #expect(first)
        #expect(other)
        #expect(!again)
        #expect(book.entries.count == 2)
        #expect(book.entries.first?.extensionID == "deck")
        #expect(book.entries.first?.count == 2)
        #expect(book.entries.first?.timestamp == moment.addingTimeInterval(60))
        // Same words, different extension: two problems, not one said twice.
        let elsewhere = book.record(entry("hand", "no reply within 2 seconds"))
        #expect(elsewhere)
        #expect(book.entries.count == 3)
    }

    @Test("a full book drops the oldest and keeps the newest")
    func staysBounded() {
        var book = ExtensionLogBook()
        for index in 0 ... ExtensionLogBook.capacity {
            book.record(entry("deck", "clip \(index) failed", at: TimeInterval(index)))
        }
        #expect(book.entries.count == ExtensionLogBook.capacity)
        #expect(book.entries.first?.message == "clip \(ExtensionLogBook.capacity) failed")
        #expect(!book.entries.contains { $0.message == "clip 0 failed" })
    }

    @Test("entries are filtered to the extension whose page is open")
    func filtersByExtension() {
        var book = ExtensionLogBook()
        book.record(entry("deck", "one"))
        book.record(entry(nil, "unreadable manifest at broken.json"))
        book.record(entry("hand", "two"))
        #expect(book.entries(about: "deck").map(\.message) == ["one"])
        // The unattributed one belongs to no page, which is why the list page
        // shows the whole log.
        #expect(book.entries(about: "").isEmpty)
    }
}

/// What utt reads off launchctl, and the log path a manifest may name.
struct ExtensionDaemonTests {
    /// Straight off `launchctl list com.example.daemon` for a job crash-looping on a
    /// port that was already taken.
    private let crashed = """
        {
        \t"LimitLoadToSessionType" = "Aqua";
        \t"Label" = "com.example.daemon";
        \t"OnDemand" = false;
        \t"LastExitStatus" = 36608;
        };
        """

    @Test("a job with no pid and a bad exit status is crashed, not stopped")
    func readsTheExitStatus() {
        let report = ExtensionDaemon.report(fromList: crashed)
        #expect(report.pid == nil)
        #expect(report.lastExitStatus == 36608)
        let running = ExtensionDaemon.report(fromList: crashed
            .replacingOccurrences(of: "\"OnDemand\" = false;", with: "\"PID\" = 20779;"))
        #expect(running.pid == 20779)
        // A job that was asked to stop exited cleanly, and that is not a crash.
        #expect(ExtensionDaemon.report(fromList: "{\n\t\"LastExitStatus\" = 0;\n};").lastExitStatus == 0)
        #expect(ExtensionDaemon.report(fromList: "nothing to say").pid == nil)
    }

    @Test("a log path utt would not point the Finder at is dropped")
    func refusesAnUnusableLogPath() {
        #expect(ExtensionDaemon(label: "com.example.daemon", log: "/tmp/d.log").logURL != nil)
        for path in ["d.log", "~/Library/Logs/d.log", "/tmp/../../etc/passwd", "/tmp/", "/tmp/d\n.log"] {
            #expect(ExtensionDaemon(label: "com.example.daemon", log: path).logURL == nil, "\(path)")
        }
        #expect(ExtensionDaemon(label: "com.example.daemon").logURL == nil)
    }

    /// The manifest is rebuilt field by field, so a capability that is not passed
    /// through there decodes fine and is silently gone by the time a view reads it.
    @Test("the log path survives sanitizing")
    func survivesSanitizing() throws {
        let manifest = ExtensionManifest(
            id: "deck", name: "Deck",
            daemon: ExtensionDaemon(label: "com.example.daemon", log: "/tmp/d.log")
        )
        let clean = try #require(manifest.sanitized())
        #expect(clean.daemon?.log == "/tmp/d.log")
        let decoded = try JSONDecoder().decode(
            ExtensionManifest.self,
            from: Data(#"{"id": "deck", "name": "Deck", "daemon": {"label": "com.example.daemon", "log": "/tmp/d.log"}}"#.utf8)
        )
        #expect(decoded.daemon?.logURL?.path() == "/tmp/d.log")
    }
}
