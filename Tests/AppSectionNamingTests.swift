import Testing
import UttCore
@testable import utt

/// `utt://show?section=…` is the only way to move the window from outside it, so
/// the matcher is what a caller — a script, an agent — actually types against.
@MainActor
struct AppSectionNamingTests {
    private let deckhand = ExtensionManifest(id: "deckhand", name: "Deckhand")

    @Test("a short lower-case name reaches a page whose title has spaces and punctuation")
    func squashedPrefix() {
        #expect(AppSection.named("sounds", extensions: []) == .sounds)
        #expect(AppSection.named("Sounds & Indicator", extensions: []) == .sounds)
        #expect(AppSection.named("api", extensions: []) == .api)
        #expect(AppSection.named("transcripts", extensions: []) == .history)
        #expect(AppSection.named("replace", extensions: []) == .replacements)
    }

    /// The rail's order is the tie-break, and it is the reason `extensions` cannot
    /// start resolving to an extension the day someone installs one called "Extensionsomething".
    @Test("extensions keeps the page and an extension answers to its own id")
    func extensionsVersusAExtension() {
        #expect(AppSection.named("extensions", extensions: [deckhand]) == .extensions)
        #expect(AppSection.named("deckhand", extensions: [deckhand]) == .extension(deckhand))
        #expect(AppSection.named("extension:deckhand", extensions: [deckhand]) == .extension(deckhand))
    }

    /// The Text page became three stages and the retention page became Saving, so
    /// both names a caller may already have written are dead as sections. They are
    /// answered anyway — a script that opened `?section=text` is not rewritten by
    /// the rail being reorganised.
    @Test("the names the rail dropped still land somewhere")
    func retiredNames() {
        #expect(AppSection.named("text", extensions: []) == .replacements)
        #expect(AppSection.named("history", extensions: []) == .saving)
        #expect(AppSection.named("cleanup", extensions: []) == .cleanup)
        #expect(AppSection.named("saving", extensions: []) == .saving)
    }

    @Test("nothing matches nothing")
    func noMatch() {
        #expect(AppSection.named("", extensions: []) == nil)
        #expect(AppSection.named("   ", extensions: []) == nil)
        #expect(AppSection.named("nosuchpage", extensions: []) == nil)
    }
}
