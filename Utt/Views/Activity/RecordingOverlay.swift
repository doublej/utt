import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// The recording indicator, front and centre on the screen.
///
/// Recording happens in somebody else's app: the window is closed or collapsed to
/// the pill, so a mark drawn inside the window is a mark nobody sees. This is a
/// borderless panel above everything instead, on the same `DotMatrixDriver` clock
/// as the menu bar icon and the window marks.
///
/// **Non-activating, mouse-transparent, never key.** utt pastes into whatever app
/// is frontmost; a panel that takes focus would break the one thing the app does.
@MainActor
final class RecordingOverlay {
    private let panel: NSPanel

    /// Panel geometry is fixed at launch. Resizing a window under a live SwiftUI
    /// hosting view fights its layout, and `panelSize` only ever needs to be wide
    /// enough for the darkening to reach zero — an edit takes effect on relaunch.
    private static var side: CGFloat { OverlayStyleStore.shared.style.panelSize }

    init(store: StoreOf<AppFeature>) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // Above ordinary windows and full-screen apps, and present on every space:
        // the point is to be visible without going to look for it.
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle
        ]

        // Ordered front for the whole run, drawing nothing while idle. Showing and
        // hiding from AppKit would mean observing the store from outside SwiftUI;
        // letting the panel's own content decide costs one transparent rect.
        panel.contentView = NSHostingView(
            rootView: RecordingOverlayView(store: store) { [weak panel] in
                guard let panel else { return }
                Self.centerOnActiveScreen(panel)
            }
        )
        Self.centerOnActiveScreen(panel)
        panel.orderFrontRegardless()
    }

    /// Re-centred at every recording, not once at launch: the display the mouse is
    /// on is the one the user is working on, and it changes.
    private static func centerOnActiveScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        panel.setFrameOrigin(
            NSPoint(x: frame.midX - side / 2, y: frame.midY - side / 2)
        )
    }
}

private struct RecordingOverlayView: View {
    let store: StoreOf<AppFeature>
    let onRecordingStarted: () -> Void

    private var recording: Bool { store.transcription.isRecording }
    private var style: OverlayStyle { OverlayStyleStore.shared.style }

    var body: some View {
        ZStack {
            if recording || OverlayStyleStore.isPreviewing {
                indicator.transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.2), value: recording)
        .onChange(of: recording) { _, isRecording in
            if isRecording { onRecordingStarted() }
        }
    }

    /// Four layers, and the order is the effect: black falling off to nothing at the
    /// edges, then the lit dots added onto it at two blur scales — wide and faint for
    /// the halo, tight and bright for the filament — then the crisp grid on top.
    ///
    /// Two things do the heavy lifting. `.plusLighter` *adds* rather than paints, and
    /// only reads as emitted light over something dark, which is the darkening's
    /// second job. And `colorMode: .extendedLinear` performs that addition in linear
    /// space: light sums linearly, so summing sRGB values instead turns overlapping
    /// halos grey and flat. Every number here comes from `overlay.json`.
    private var indicator: some View {
        ZStack {
            RadialGradient(
                stops: Self.darkeningStops(style),
                center: .center,
                startRadius: 0,
                endRadius: style.panelSize / 2
            )
            mark(litOnly: true)
                .blur(radius: style.haloBlur)
                .blendMode(.plusLighter)
                .opacity(style.haloIntensity)
            mark(litOnly: true)
                .blur(radius: style.glowBlur)
                .blendMode(.plusLighter)
                .opacity(style.glowIntensity)
            mark(litOnly: false)
            dither
        }
        .compositingGroup()
        .drawingGroup(opaque: false, colorMode: style.linearBlending ? .extendedLinear : .nonLinear)
    }

    /// The falloff, sampled off a smootherstep curve.
    ///
    /// Hand-placed stops interpolate linearly between each other, so every stop is a
    /// kink in the slope — and the eye finds a slope change far more readily than it
    /// finds a value change, which is why the old four-stop ramp read as concentric
    /// rings. Smootherstep (`6t⁵-15t⁴+10t³`) has zero first *and* second derivative at
    /// both ends: the darkening arrives out of nothing and leaves into nothing with no
    /// edge anywhere, which is the whole trick to sitting on a white document unnoticed.
    private static func darkeningStops(_ style: OverlayStyle) -> [Gradient.Stop] {
        let steps = 32
        return (0...steps).map { step in
            let location = Double(step) / Double(steps)
            let edge = min(1, location / max(0.01, style.darkeningRadius))
            let fade = 1 - edge * edge * edge * (edge * (edge * 6 - 15) + 10)
            return Gradient.Stop(
                color: .black.opacity(style.darkening * fade), location: location
            )
        }
    }

    /// One pixel of noise per output pixel, added last so it lands *before* the
    /// framebuffer rounds to 8 bits — dither after quantisation is just grain.
    ///
    /// The noise lives in alpha, not in colour: against a light background it is the
    /// alpha ramp that bands, and adding white to a transparent pixel changes nothing
    /// the compositor can see.
    @ViewBuilder
    private var dither: some View {
        if style.dither > 0, let tile = Self.noiseTile {
            Rectangle()
                .fill(ImagePaint(image: Image(decorative: tile, scale: Self.pixelScale)))
                .blendMode(.plusLighter)
                .opacity(style.dither / 255)
        }
    }

    /// White, with random alpha, generated once. `shouldInterpolate: false` matters:
    /// a smoothed noise tile is a cloud texture, and clouds do not dither.
    private static let noiseTile: CGImage? = {
        let side = 128
        var pixels = [UInt8]()
        pixels.reserveCapacity(side * side * 4)
        for _ in 0..<(side * side) {
            // Premultiplied, so white at alpha n is (n, n, n, n).
            let alpha = UInt8.random(in: 0...255)
            pixels.append(contentsOf: [alpha, alpha, alpha, alpha])
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side, height: side,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }()

    /// Read once: the panel does not follow the mouse between displays mid-recording,
    /// and a tile one point across on a 1x screen is still finer than the banding.
    private static let pixelScale = NSScreen.main?.backingScaleFactor ?? 2

    private func mark(litOnly: Bool) -> some View {
        UttMark(
            size: style.markSize,
            tint: Palette.recording,
            recording: true,
            level: Double(store.transcription.meterLevel),
            litOnly: litOnly,
            hotCore: style.hotCore
        )
    }
}
