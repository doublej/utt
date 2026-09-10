//
//  ExtensionFilesTests.swift
//  UttCoreTests
//
//  Removing an extension trashes files by name, in a directory other extensions share.
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
                     "deck.transcript.json", "deck.consent.json", "deck.jobs", "deck.filter",
                     "deck.disabled"] {
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
