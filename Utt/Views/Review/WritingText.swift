import SwiftUI
import UttCore

/// Live words that write themselves onto the card: each new letter fades up, sharpens
/// and settles into place a beat after the one before it. Letters already on screen
/// stay still, so the eye only goes to what just arrived.
struct WritingText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What is drawn, one update behind `text`: the split has to change in the same
    /// frame as the animation restarts, or the new letters flash in fully first.
    @State private var shown = (settled: "", full: "")

    var body: some View {
        let fresh = String(shown.full.dropFirst(shown.settled.count))
        let timing = WritingTiming(letters: fresh.count)
        Text("\(Text(verbatim: shown.settled))\(Text(verbatim: fresh).customAttribute(FreshLetters()))")
            .keyframeAnimator(initialValue: WritingTiming.done, trigger: shown.full) { [reduceMotion] content, elapsed in
                content.textRenderer(WritingRenderer(elapsed: elapsed, timing: timing, reduceMotion: reduceMotion))
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(0)
                    LinearKeyframe(timing.total, duration: timing.total)
                }
            }
            .onChange(of: text, initial: true) { _, now in
                shown = (WritingSplit.settled(previous: shown.full, current: now), now)
            }
    }
}

/// When each new letter starts and how long it takes. The stagger shrinks for a long
/// burst so a whole sentence arriving at once is still written in well under half a
/// second, never trailing behind the next update.
private struct WritingTiming {
    static let done = 60.0
    static let letter = 0.2

    let stagger: Double
    let total: Double

    init(letters: Int) {
        stagger = min(0.025, 0.18 / Double(max(letters, 1)))
        total = stagger * Double(max(letters - 1, 0)) + Self.letter
    }

    func progress(of index: Int, at elapsed: Double) -> Double {
        min(max((elapsed - stagger * Double(index)) / Self.letter, 0), 1)
    }
}

private struct FreshLetters: TextAttribute {}

private struct WritingRenderer: TextRenderer {
    let elapsed: Double
    let timing: WritingTiming
    let reduceMotion: Bool

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0
        for run in layout.flatMap(\.self) {
            guard run[FreshLetters.self] != nil else {
                context.draw(run)
                continue
            }
            for slice in run {
                let progress = timing.progress(of: index, at: elapsed)
                index += 1
                var letter = context
                letter.opacity = progress
                if !reduceMotion, progress < 1 {
                    letter.translateBy(x: 0, y: (1 - progress) * 3)
                    letter.addFilter(.blur(radius: (1 - progress) * 3))
                }
                letter.draw(slice)
            }
        }
    }
}

/// The first pass giving way to the real transcript: the outgoing card blurs out
/// while the incoming one sharpens in. Paired with a matched geometry effect on the
/// words, the provisional text reads as resolving into the final text in place.
struct ResolveTransition: Transition {
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity || reduceMotion ? 0 : 6)
    }
}
