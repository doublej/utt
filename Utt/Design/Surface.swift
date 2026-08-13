import SwiftUI

/// Flat content surface. Use for cards, rows, list items inside the window.
/// Never apply on top of another glass — produces "muddy 2005 UI" look.
struct ContentSurface: ViewModifier {
    var radius: CGFloat = Radius.medium

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.strokeHairline, lineWidth: 0.5)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            }
    }
}

/// Floating chrome surface (Liquid Glass). Use only for navigation and control
/// overlays that float above content (command bars, pills, sheet headers).
/// Embedded content — cards, rows, and recorder strips — uses `ContentSurface`
/// or a plain stroke instead.
///
/// Takes a shape rather than a radius because the caller may not want a rounded
/// rectangle, and clipping one shape to another is what makes curves look jagged:
/// a `.continuous` corner and a circular arc do not coincide, so the clip slices
/// the stroke at varying depths and throws away exactly the antialiased pixels that
/// were smoothing it. One shape, drawn once, no clip.
struct ChromeGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var stroke: Bool = true

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: shape)
            .overlay(strokeOverlay)
            .overlay {
                // Inner bevel: inset dark stroke that reads as depth.
                shape
                    .strokeBorder(Color.black.opacity(0.20), lineWidth: 1)
                    .padding(0.5)
            }
            .overlay {
                // `strokeBorder`, not `stroke`: a centred stroke puts half its width
                // outside the silhouette, which then has to be trimmed by something.
                shape
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            }
    }

    @ViewBuilder private var strokeOverlay: some View {
        if stroke {
            shape.strokeBorder(Palette.strokeGlass, lineWidth: 0.5)
        }
    }
}

extension View {
    func contentSurface(radius: CGFloat = Radius.medium) -> some View {
        modifier(ContentSurface(radius: radius))
    }

    func chromeGlass(radius: CGFloat = Radius.medium, stroke: Bool = true) -> some View {
        chromeGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous), stroke: stroke)
    }

    func chromeGlass(in shape: some InsettableShape, stroke: Bool = true) -> some View {
        modifier(ChromeGlass(shape: shape, stroke: stroke))
    }
}
