import Foundation

/// Every knob the recording overlay draws itself with, in one file you can edit
/// without a rebuild: `~/Library/Application Support/dev.jurrejan.utt/overlay.json`.
///
/// Defaults are the shipped look. Anything missing from the file falls back to its
/// default — every key decodes independently, so a half-written file still loads and
/// a key added in a later version never invalidates one written today.
///
/// The values are what the bloom literature calls the artist parameters: a threshold
/// (here, `litOnly` drops the dim cells), two blur scales, an additive intensity per
/// scale, and a core brightness. See `docs/dot-matrix.md`.
public struct OverlayStyle: Equatable, Codable, Sendable {
    /// Side of the panel in points. Must stay comfortably wider than the darkening,
    /// or the gradient hits the window edge and reads as a grey square.
    public var panelSize: Double = 260

    /// Side of the dot grid in points. 51 is three times the in-window mark.
    public var markSize: Double = 51

    /// Opacity of the black directly behind the grid, 0...1.
    public var darkening: Double = 0.78

    /// Where the darkening has fallen to nothing, as a fraction of half the panel.
    /// Below 1 the falloff finishes early and leaves a hard ring.
    public var darkeningRadius: Double = 1.0

    /// Dither amplitude, in levels of the 8-bit output. A smooth alpha ramp this
    /// wide crosses each of its 255 available levels over tens of points, and the
    /// eye reads the flat stretches between them as rings (Mach banding) — worst
    /// over a light background, where the ramp is the only thing on screen. Noise
    /// of about one level, added before the framebuffer rounds, turns the step
    /// into a gradient the eye averages back out. 0 disables it.
    public var dither: Double = 1.6

    /// Wide, faint bloom: the halo you see before you see the dots.
    public var haloBlur: Double = 11
    public var haloIntensity: Double = 0.85

    /// Tight, bright bloom: the filament right at the dot.
    public var glowBlur: Double = 3
    public var glowIntensity: Double = 1.0

    /// How far each lit dot's centre is pushed towards white, 0...1. Real emitters
    /// saturate at the middle and only show their colour in the falloff; a flat disc
    /// of pure colour is the single biggest tell that something is drawn, not lit.
    public var hotCore: Double = 0.7

    /// Composite the additive layers in extended-linear space instead of sRGB.
    /// Adding light is a linear operation — done in sRGB the halo goes muddy and
    /// grey where it overlaps. Off is the cheaper, flatter look.
    public var linearBlending: Bool = true

    public init() {}

    /// Decodes each key on its own so an unknown or missing one is not fatal.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func read(_ key: CodingKeys, _ fallback: Double) -> Double {
            (try? container.decodeIfPresent(Double.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        let defaults = OverlayStyle()
        panelSize = read(.panelSize, defaults.panelSize)
        markSize = read(.markSize, defaults.markSize)
        darkening = read(.darkening, defaults.darkening)
        darkeningRadius = read(.darkeningRadius, defaults.darkeningRadius)
        dither = read(.dither, defaults.dither)
        haloBlur = read(.haloBlur, defaults.haloBlur)
        haloIntensity = read(.haloIntensity, defaults.haloIntensity)
        glowBlur = read(.glowBlur, defaults.glowBlur)
        glowIntensity = read(.glowIntensity, defaults.glowIntensity)
        hotCore = read(.hotCore, defaults.hotCore)
        linearBlending = (try? container.decodeIfPresent(Bool.self, forKey: .linearBlending))
            .flatMap { $0 } ?? defaults.linearBlending
    }

    /// Reads the file, or returns the defaults when it is absent or unreadable.
    /// A malformed file must not stop the overlay from drawing — you would be left
    /// with no indicator and no clue why.
    public static func loaded(from url: URL? = try? .uttOverlayStyleFile) -> OverlayStyle {
        guard let url, let data = try? Data(contentsOf: url) else { return OverlayStyle() }
        return (try? JSONDecoder().decode(OverlayStyle.self, from: data)) ?? OverlayStyle()
    }

    /// Writes the current values, pretty-printed and key-sorted so the file stays
    /// diffable and readable as a starting point for editing.
    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

public extension URL {
    /// Where `OverlayStyle` is read from. Hand-edited, never written by the app
    /// except by `just overlay-preview` seeding the defaults.
    static var uttOverlayStyleFile: URL {
        get throws { try uttApplicationSupport.appending(component: "overlay.json") }
    }
}
