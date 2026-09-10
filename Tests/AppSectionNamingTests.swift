import Testing
import UttCore
@testable import utt

/// `utt://show?section=…` is the only way to move the window from outside it, so
/// the matcher is what a caller — a script, an agent — actually types against.
@MainActor
struct AppSectionNamingTests {
    private let deckhand = PluginManifest(id: "deckhand", name: "Deckhand")

    @Test("a short lower-case name reaches a page whose title has spaces and punctuation")
    func squashedPrefix() {
        #expect(AppSection.named("sounds", plugins: []) == .sounds)
        #expect(AppSection.named("Sounds & Indicator", plugins: []) == .sounds)
        #expect(AppSection.named("api", plugins: []) == .api)
        #expect(AppSection.named("transcripts", plugins: []) == .history)
    }

    /// The rail's order is the tie-break, and it is the reason `plugins` cannot
    /// start resolving to a plugin the day someone installs one called "Pluginsomething".
    @Test("plugins keeps the page and a plugin answers to its own id")
    func pluginsVersusAPlugin() {
        #expect(AppSection.named("plugins", plugins: [deckhand]) == .plugins)
        #expect(AppSection.named("deckhand", plugins: [deckhand]) == .plugin(deckhand))
        #expect(AppSection.named("plugin:deckhand", plugins: [deckhand]) == .plugin(deckhand))
    }

    @Test("nothing matches nothing")
    func noMatch() {
        #expect(AppSection.named("", plugins: []) == nil)
        #expect(AppSection.named("   ", plugins: []) == nil)
        #expect(AppSection.named("nosuchpage", plugins: []) == nil)
    }
}
