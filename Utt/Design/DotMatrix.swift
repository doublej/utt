import SwiftUI

/// The shapes and the cadence, apart from any one way of drawing them: the window
/// draws the grid with `Canvas`, the menu bar has to hand AppKit a finished image.
///
/// Patterns are frames of one long show: consecutive entries are frames of a
/// single animation (heart, star, coffee steam, the "utt." marquee), and the
/// driver steps through the whole list in order.
enum DotMatrix {
    /// Lit cells on a 6×6 grid. Index 0 is the default 'u'.
    static let patterns: [Set<Int>] = [
        [7, 8, 13, 14, 21, 22, 27, 28],       // 'u' shape (original)
        [14, 15, 20, 21],                      // centered dot/square
        [0, 5, 7, 10, 25, 28, 30, 35],        // corner dots
        [8, 9, 14, 15, 20, 21, 26, 27],       // vertical bar
        [0, 7, 14, 21, 28, 35],               // diagonal
        [7, 8, 9, 10, 13, 16, 19, 22, 25, 26, 27, 28], // ring
        // Heartbeat: a pulse spike travels the baseline, then a double beat.
        [18, 24, 30, 31, 32, 33, 34, 35],     // ecg pulse, far left
        [20, 26, 30, 31, 32, 33, 34, 35],     // ecg pulse, mid-left
        [22, 28, 30, 31, 32, 33, 34, 35],     // ecg pulse, mid-right
        [22, 25, 28, 30, 31, 32, 33, 34, 35], // ecg lub-dub
        // A heart that beats: lub, dub, and the dub rings.
        [19, 20, 22, 23, 25, 26, 27, 28, 32, 33], // heart, lub (small)
        [1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 26, 27], // heart, dub (big)
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 26, 27, 32, 33], // heart, dub glow
        [19, 20, 22, 23, 25, 26, 27, 28, 32, 33], // heart, lub (small)
        // A one-character conversation: grin, wink, gasp, blep.
        [1, 4, 7, 10, 19, 20, 21, 22, 26, 27], // face, grin
        [1, 7, 9, 10, 19, 20, 21, 22, 26, 27], // face, wink
        [1, 4, 7, 10, 20, 21, 26, 27],        // face, surprised 'o'
        [1, 4, 7, 10, 19, 20, 21, 22, 24, 25], // face, blep
        // Arcade chase, four frames of it.
        [7, 8, 13, 14, 19, 20, 21],           // pac-man, mouth open
        [7, 8, 9, 13, 14, 15, 19, 20, 21],    // pac-man, mouth closed
        [9, 10, 11, 15, 21, 22, 23],          // ghost
        [8, 9, 14, 15, 19, 20, 21],           // pac-man flipped, chasing
        // Rocket launch, ending in a pop.
        [20, 25, 26, 27, 30, 31, 32, 33, 34], // rocket on the pad
        [14, 19, 20, 21, 24, 25, 26, 27, 28, 32], // ignition, small flame
        [8, 13, 14, 15, 18, 19, 20, 21, 22, 26, 32], // liftoff, big flame
        [7, 8, 9, 13, 14, 15, 19, 20, 21],    // burst
        // Moon waxing thick.
        [8, 9, 13, 19, 26, 27],               // crescent
        [8, 13, 14, 19, 20, 26],              // first quarter
        [8, 9, 13, 14, 15, 19, 20, 21, 26, 27], // gibbous
        [8, 9, 13, 14, 15, 16, 19, 20, 21, 22, 26, 27], // full moon
        // Equalizer bars, bottom-anchored.
        [30, 25, 31, 20, 26, 32, 27, 33, 34, 29, 35], // eq 1-2-3-2-1-2
        [18, 24, 30, 25, 31, 32, 33, 28, 34, 23, 29, 35], // eq 3-2-1-1-2-3
        [24, 30, 31, 26, 32, 21, 27, 33, 28, 34, 35], // eq 2-1-2-3-2-1
        [30, 19, 25, 31, 26, 32, 27, 33, 22, 28, 34, 35], // eq 1-3-2-2-3-1
        // Two more moods: cool shades (that nod), then smitten.
        [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 22, 23, 25, 26, 27, 28], // face, sunglasses
        [7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 22, 23, 24, 25, 28, 29, 31, 32, 33, 34], // face, sunglasses nod
        [1, 2, 3, 4, 7, 8, 10, 11, 14, 16, 18, 19, 20, 21, 22, 23], // face, heart-eyes
        // A star with a sparkle that orbits it.
        [0, 2, 3, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 26, 27, 32, 33], // star, twinkle
        [2, 3, 5, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 26, 27, 32, 33], // star, twinkle
        [2, 3, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 26, 27, 32, 33, 35], // star, twinkle
        [2, 3, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 26, 27, 30, 32, 33], // star, twinkle
        // A note that hops.
        [1, 2, 7, 8, 14, 15, 20, 21, 26, 27, 31, 32, 33, 34], // note, rest
        [1, 2, 7, 8, 14, 15, 20, 21, 25, 26, 27, 28], // note, hop
        [1, 2, 7, 8, 14, 15, 20, 21, 26, 27, 31, 32, 33, 34], // note, rest
        // Lightning, then the strike flashes.
        [2, 3, 8, 9, 10, 13, 14, 15, 18, 19, 20, 26, 27, 28, 33, 34], // bolt
        [0, 2, 3, 5, 8, 9, 10, 13, 14, 15, 18, 19, 20, 26, 27, 28, 30, 33, 34, 35], // bolt, flash
        // Snowflake rotating through x, diamond, plus, diamond.
        [0, 5, 7, 10, 14, 15, 20, 21, 25, 28, 30, 35], // snowflake
        [2, 3, 7, 10, 14, 15, 20, 21, 25, 28, 32, 33], // snowflake
        [2, 8, 14, 15, 20, 21, 26, 32], // snowflake
        [2, 3, 7, 10, 14, 15, 20, 21, 25, 28, 32, 33], // snowflake
        // The checkmark draws itself.
        [0, 6, 13], // check, stroke
        [0, 6, 13, 20, 27], // check, stroke
        [0, 6, 13, 20, 27, 34, 35], // check
        // Arrow bounces down, hits, and bounces back.
        [2, 8, 12, 13, 14, 15, 16, 17, 20, 26], // arrow, up
        [8, 14, 18, 19, 20, 21, 22, 23, 26, 32], // arrow, down
        [8, 14, 18, 19, 20, 21, 22, 23, 26, 30, 32, 35], // arrow, strike
        // Props from the everyday: a saucer, a coffee, a mushroom, an hourglass.
        [0, 2, 3, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 25, 26, 27, 28, 32, 33], // saucer, light
        [2, 3, 5, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 25, 26, 27, 28, 32, 33], // saucer, light
        [2, 3, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 25, 26, 27, 28, 32, 33, 35], // saucer, light
        [2, 3, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 25, 26, 27, 28, 30, 32, 33], // saucer, light
        // Coffee: steam rises, thins, and is gone.
        [7, 9, 13, 14, 15, 16, 18, 23, 24, 29, 31, 32, 33, 34], // coffee, steam low
        [1, 3, 13, 14, 15, 16, 18, 23, 24, 29, 31, 32, 33, 34], // coffee, steam mid
        [2, 13, 14, 15, 16, 18, 23, 24, 29, 31, 32, 33, 34], // coffee, steam high
        [13, 14, 15, 16, 18, 23, 24, 29, 31, 32, 33, 34], // coffee, still
        // Mushroom sways on its stem, cap rooted to the spot.
        [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 14, 15, 20, 21, 26, 27, 31, 32, 33, 34], // mushroom, sway
        [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 13, 14, 19, 20, 25, 26, 31, 32, 33, 34], // mushroom, sway
        [1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 15, 16, 21, 22, 27, 28, 31, 32, 33, 34], // mushroom, sway
        // Hourglass: the sand pours through the neck and settles.
        [1, 2, 3, 4, 6, 11, 14, 15, 18, 20, 21, 23, 24, 29, 31, 32, 33, 34], // hourglass, pour
        [1, 2, 3, 4, 6, 11, 18, 20, 21, 23, 24, 26, 27, 29, 31, 32, 33, 34], // hourglass, stream
        [1, 2, 3, 4, 6, 11, 18, 23, 24, 25, 26, 27, 28, 29, 31, 32, 33, 34], // hourglass, settled
        // Pong rally: the ball crosses row 2, the paddle waits at the net.
        [11, 14, 17, 23, 29], // pong, ball out wide
        [11, 15, 17, 23, 29], // pong, ball mid-court
        [11, 16, 17, 23, 29], // pong, ball closing
        [11, 17, 23, 29], // pong, paddle strike
        // The wordmark as a marquee: u, t, t, and the period scroll right to
        // left, each letter a full three columns wide on the six-wide grid.
        [0, 2, 4, 5, 6, 8, 11, 12, 14, 17, 18, 20, 23, 24, 26, 29, 30, 31, 32, 35], // utt. marquee
        [1, 3, 4, 5, 7, 10, 13, 16, 19, 22, 25, 28, 30, 31, 34], // utt. marquee
        [0, 2, 3, 4, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33], // utt. marquee
        [1, 2, 3, 5, 8, 14, 20, 26, 32], // utt. marquee
        [0, 1, 2, 4, 5, 7, 11, 13, 17, 19, 23, 25, 29, 31, 35], // utt. marquee
        [0, 1, 3, 4, 5, 6, 10, 12, 16, 18, 22, 24, 28, 30, 34], // utt. marquee
        [0, 2, 3, 4, 9, 15, 21, 27, 33], // utt. marquee
        [1, 2, 3, 8, 14, 20, 26, 32, 35], // utt. marquee
        [0, 1, 2, 7, 13, 19, 25, 31, 34], // utt. marquee
        [0, 1, 6, 12, 18, 24, 30, 33], // utt. marquee
        [0, 32], // utt. marquee
        [31], // utt. marquee
        [30], // utt. marquee
        [] // utt. marquee
    ]

    /// How often the phase accumulator advances. Fixed, so a changing level never
    /// restarts the timer and starves the cycle.
    static let tick: TimeInterval = 0.05

    /// Seconds per pattern at silence and at full scale.
    private static let slowestCycle: TimeInterval = 6
    private static let fastestCycle: TimeInterval = 0.1

    /// Peak amplitude is a terrible speed knob — ordinary speech peaks around 0.1,
    /// so a linear map spends its whole range on volumes nobody produces. The same
    /// dBFS scale the VU meters use puts speech at roughly 0.6...0.9 instead, and
    /// the interval is geometric so every step up is a constant factor faster.
    static func cycleInterval(for level: Double) -> TimeInterval {
        guard level > 0.001 else { return slowestCycle }
        let normalized = min(max((max(-60, 20 * log10(level)) + 60) / 60, 0), 1)
        return slowestCycle * pow(fastestCycle / slowestCycle, normalized)
    }

    /// Where dot `index` sits in a grid `size` points wide. Six columns across the
    /// full width, each dot centred in its cell — any other divisor leaves the
    /// grid sitting off-centre in its frame.
    static func rect(for index: Int, size: CGFloat, lit: Bool) -> CGRect {
        let step = size / 6
        let radius = step * (lit ? 0.34 : 0.24)
        return CGRect(
            x: step * (0.5 + CGFloat(index % 6)) - radius,
            y: step * (0.5 + CGFloat(index / 6)) - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}
