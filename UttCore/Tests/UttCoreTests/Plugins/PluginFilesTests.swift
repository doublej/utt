//
//  PluginFilesTests.swift
//  UttCoreTests
//
//  Removing a plugin trashes files by name, in a directory other plugins share.
//

import Foundation
import Testing
@testable import UttCore

struct PluginFilesTests {
    @Test("removal takes exactly the plugin's own files")
    func ownsItsFiles() {
        for name in ["deck.json", "deck.values.json", "deck.status.json", "deck.action.json",
                     "deck.transcript.json", "deck.jobs", "deck.filter", "deck.disabled"] {
            #expect(PluginManifest.file(name, belongsTo: "deck"), "\(name)")
        }
        // Another plugin whose id merely starts the same way, and ids with dots.
        #expect(!PluginManifest.file("deck.hand.json", belongsTo: "deck"))
        #expect(!PluginManifest.file("deckhand.json", belongsTo: "deck"))
        #expect(PluginManifest.file("deck.hand.json", belongsTo: "deck.hand"))
        #expect(!PluginManifest.file("deck.notes", belongsTo: "deck"))
        #expect(!PluginManifest.file("deck", belongsTo: "deck"))
    }
}
