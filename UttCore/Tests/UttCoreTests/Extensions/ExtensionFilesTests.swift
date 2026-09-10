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
        for name in ["deck.json", "deck.values.json", "deck.status.json", "deck.action.json",
                     "deck.transcript.json", "deck.jobs", "deck.filter", "deck.disabled"] {
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
