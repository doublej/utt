import Foundation
import Testing
@testable import UttCore

@Suite("Overlay style file")
struct OverlayStyleTests {
    /// The whole point of the file is hand-editing, so a file naming one knob has to
    /// leave the rest alone rather than zeroing them.
    @Test
    func aPartialFileKeepsTheDefaultsForEverythingElse() throws {
        let json = #"{"hotCore": 0.2, "haloBlur": 40}"#
        let style = try JSONDecoder().decode(OverlayStyle.self, from: Data(json.utf8))

        #expect(style.hotCore == 0.2)
        #expect(style.haloBlur == 40)
        #expect(style.darkening == OverlayStyle().darkening)
        #expect(style.linearBlending == OverlayStyle().linearBlending)
    }

    /// A typo mid-edit must not leave the user with no indicator and no explanation.
    @Test
    func aMalformedFileFallsBackToTheDefaults() throws {
        let url = URL.temporaryDirectory.appending(component: "overlay-broken-\(UUID()).json")
        try Data("{ not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(OverlayStyle.loaded(from: url) == OverlayStyle())
    }

    @Test
    func aMissingFileIsNotAnError() {
        let missing = URL.temporaryDirectory.appending(component: "overlay-absent-\(UUID()).json")
        #expect(OverlayStyle.loaded(from: missing) == OverlayStyle())
    }

    /// What `just overlay-preview` writes must be something the app can read back.
    @Test
    func whatItWritesItCanRead() throws {
        let url = URL.temporaryDirectory.appending(component: "overlay-roundtrip-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var style = OverlayStyle()
        style.hotCore = 0.33
        try style.write(to: url)

        #expect(OverlayStyle.loaded(from: url) == style)
    }
}
