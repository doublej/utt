import SwiftUI

/// The one clock every grid runs on. A timer per view drifts: two marks on screen
/// start their cycles at different moments and never agree again, which reads as a
/// bug the moment the window and the menu bar are visible together.
///
/// Never stopped. The menu bar icon is on screen for the whole run, so the only
/// thing a stop condition could ever do is freeze the mark by accident.
@MainActor
@Observable
final class DotMatrixDriver {
    static let shared = DotMatrixDriver()

    private(set) var patternIndex = 0
    /// Written by whichever marks are on screen — they all pass the same meter.
    var level: Double = 0

    private var phase: Double = 0
    private var timer: Timer?

    var pattern: Set<Int> { DotMatrix.patterns[patternIndex % DotMatrix.patterns.count] }

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: DotMatrix.tick, repeats: true) { _ in
            Task { @MainActor in Self.shared.advance() }
        }
    }

    private func advance() {
        phase += DotMatrix.tick / DotMatrix.cycleInterval(for: level)
        guard phase >= 1 else { return }
        phase = 0
        patternIndex = (patternIndex + 1) % DotMatrix.patterns.count
    }
}

/// The one-shot counterpart to `DotMatrixDriver`: plays a fixed list of frames
/// exactly once, then stops. `LockAnimation.frames` is the intended payload.
/// Observers read `pattern` and render it with `DotMatrix.rect` like any other
/// mark; `onFinished` fires after the last frame has been shown.
@MainActor
@Observable
final class OneShotPatternPlayer {
    private let frames: [Set<Int>]
    private let interval: TimeInterval

    private(set) var patternIndex = 0
    private(set) var isPlaying = false
    /// Called after the final frame, once the player has stopped.
    var onFinished: (() -> Void)?

    var pattern: Set<Int> { frames[patternIndex] }

    init(frames: [Set<Int>], interval: TimeInterval) {
        self.frames = frames
        self.interval = interval
    }

    func play() {
        guard !frames.isEmpty, !isPlaying else { return }
        isPlaying = true
        patternIndex = 0
        scheduleAdvance()
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private var timer: Timer?

    private func scheduleAdvance() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
    }

    private func advance() {
        guard patternIndex + 1 < frames.count else {
            isPlaying = false
            timer = nil
            onFinished?()
            return
        }
        patternIndex += 1
        scheduleAdvance()
    }
}

/// utty's dot-matrix mark with animated pattern transitions. The lit cells form
/// shapes on a 6×6 grid. Patterns cycle on the shared driver, faster the louder
/// the input; recording shows as the red tint, not as a separate shape.
struct UttMark: View {
    var size: CGFloat = 18
    var tint: Color = Palette.accent
    var recording = false
    var level: Double = 0
    /// Drops the dim cells. Only the bloom layer of the recording overlay wants
    /// this — blurring the unlit grid smears the black it is supposed to sit on.
    var litOnly = false
    /// How far a lit dot's centre is pushed towards white, 0...1. A real emitter
    /// saturates in the middle and only shows its colour in the falloff; a flat
    /// disc of pure colour is what makes a drawn dot look drawn. 0 keeps it flat,
    /// which is what the 16pt marks want — the gradient is invisible at that size.
    var hotCore: Double = 0
    /// Splits every cell into a `subdivision`×`subdivision` block of dots at the
    /// *same* pitch, so 2 turns one dot into four and the mark grows to twice the
    /// size rather than the dots growing. The shapes are unchanged — they are read
    /// off the same 6×6 patterns, just drawn coarser than the grid they land on.
    var subdivision: Int = 1

    @State private var dotOpacities: [Int: Double] = [:]

    private var driver: DotMatrixDriver { .shared }
    private var currentPattern: Set<Int> { driver.pattern }
    private var cycleInterval: TimeInterval { DotMatrix.cycleInterval(for: driver.level) }
    private var columns: Int { 6 * max(1, subdivision) }
    /// Lit dots follow the meter. Only while recording: at rest every other mark in
    /// the app would sit permanently dimmed, since nothing is feeding it a level.
    private var glow: Double { recording ? DotMatrix.glow(for: driver.level) : 1 }

    var body: some View {
        Canvas { context, canvasSize in
            for index in 0..<(columns * columns) {
                drawDot(index, size: canvasSize.width, in: &context)
            }
        }
        .frame(width: size * CGFloat(max(1, subdivision)), height: size * CGFloat(max(1, subdivision)))
        .accessibilityHidden(true)
        .onChange(of: level) { _, newLevel in driver.level = newLevel }
        .onChange(of: driver.patternIndex) { _, _ in animatePatternTransition() }
        .onAppear {
            initializeOpacities()
            driver.level = level
        }
    }

    private func drawDot(_ index: Int, size: CGFloat, in context: inout GraphicsContext) {
        let cell = sourceCell(for: index)
        let crossfade = dotOpacities[cell] ?? (currentPattern.contains(cell) ? 1.0 : 0.0)
        // Lit is decided on the crossfade alone. Fold the glow in first and a quiet
        // passage drops every dot below the threshold — the grid would go unlit
        // rather than dim.
        let isLit = crossfade > 0.5
        guard isLit || !litOnly else { return }
        let opacity = crossfade * glow
        let rect = DotMatrix.rect(for: index, size: size, lit: isLit, columns: columns)
        guard isLit, hotCore > 0 else {
            let color = isLit ? tint.opacity(opacity) : Color.primary.opacity(0.28)
            context.fill(Path(ellipseIn: rect), with: .color(color))
            return
        }
        // Hot in the middle, the tint's own colour by the rim. The stop at 0.55
        // keeps the white to the inner half — spread across the whole dot it stops
        // reading as a hot centre and starts reading as a washed-out one.
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: tint.mix(with: .white, by: hotCore).opacity(opacity), location: 0),
                    .init(color: tint.opacity(opacity), location: 0.55),
                    .init(color: tint.opacity(opacity), location: 1)
                ]),
                center: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endRadius: rect.width / 2
            )
        )
    }

    /// Which of the 36 authored cells a dot in the drawn grid belongs to. At
    /// `subdivision: 1` this is the identity.
    private func sourceCell(for index: Int) -> Int {
        let step = max(1, subdivision)
        return (index / columns / step) * 6 + (index % columns) / step
    }

    private func initializeOpacities() {
        for index in 0..<36 {
            dotOpacities[index] = currentPattern.contains(index) ? 1.0 : 0.0
        }
    }

    private func animatePatternTransition() {
        let target = currentPattern
        // Never let a transition outlast the cycle that triggered it, or a loud
        // signal leaves every dot stuck mid-fade.
        withAnimation(.easeInOut(duration: min(0.4, cycleInterval * 0.5))) {
            for index in 0..<36 {
                dotOpacities[index] = target.contains(index) ? 1.0 : 0.0
            }
        }
    }
}

/// Small all-caps monospaced label used to title a control inline ("MIC", "VU").
struct KickerLabel: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(tint.opacity(0.75))
    }
}

/// The wordmark: `utt` plus a period that turns red while recording.
struct UttWordmark: View {
    var size: CGFloat = 14
    var recording = false

    var body: some View {
        HStack(spacing: 0) {
            Text("utt")
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .tracking(-0.3)
                .foregroundStyle(.primary)
            Text(".")
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(recording ? Palette.recording : Palette.accent)
        }
        .accessibilityElement()
        .accessibilityLabel("utt")
    }
}
