# Dot matrix: shapes and animation

Everything about utt's dot-matrix mark. One file to read before adding a shape or
changing how it moves.

Code: `Utt/Design/DotMatrix.swift` (`enum DotMatrix` — the patterns and the
cadence), `Utt/Views/Common/UttMark.swift` (`DotMatrixDriver` + `struct UttMark`),
`Utt/Views/App/MenuBarContent.swift` (`MenuBarIcon`).

Preview: `just dot-matrix-preview` regenerates
`docs/dot-matrix-preview.html` from the pattern list and opens it — every shape
as a 6×6 board, plus an animate mode that steps the cycle like the app.

## The grid

6×6, 36 cells, numbered left to right, top to bottom:

```
 0  1  2  3  4  5
 6  7  8  9 10 11
12 13 14 15 16 17
18 19 20 21 22 23
24 25 26 27 28 29
30 31 32 33 34 35
```

`index = row * 6 + col`. Row 0 is the top.

A **pattern** is a `Set<Int>` of the lit cells. Everything not listed is drawn as
a dim small dot — the grid is always fully visible, lit cells are just bigger and
tinted.

## Adding a shape

1. Draw it on paper as six rows of six characters, `X` lit, `.` dark:

   ```
   . . . . . .        row 0 → nothing
   . X . . X .        row 1 → 7, 10
   . X . . X .        row 2 → 13, 16
   . X . . X .        row 3 → 19, 22
   . X X X X .        row 4 → 25, 26, 27, 28
   . . . . . .        row 5 → nothing
   ```

2. Read off the indices with `row * 6 + col`.
3. Add one line to `DotMatrix.patterns`, with a trailing comment naming the shape:

   ```swift
   [7, 10, 13, 16, 19, 22, 25, 26, 27, 28],  // 'u' shape
   ```

That is the whole change. The cycle picks up the new entry automatically —
`patterns.count` is read everywhere, never hardcoded. Then run
`just dot-matrix-preview` to regenerate the HTML preview with the new shape.

### Rules for a shape that reads at 16pt

- **6 to 12 lit dots.** Fewer looks like a rendering bug, more looks like a solid
  block.
- **Keep one dark row or column of margin** where you can. Shapes that touch all
  four edges lose their silhouette in the menu bar.
- **No single-dot diagonals thinner than the gap** — at 16pt a lone diagonal
  reads as noise. Diagonals need to run corner to corner (`0, 7, 14, 21, 28, 35`).
- **Test at 16pt, not in a preview blown up to 200pt.** The menu bar is the
  smallest place it appears and the one that decides whether a shape works.

## How the animation works

One timer for the whole app, owned by `DotMatrixDriver.shared`, fixed at
`DotMatrix.tick` (0.05s). Every mark — menu bar, header, collapsed pill, the large
recording indicator — reads `driver.patternIndex`, so they all show the same shape
at the same moment. A timer per view drifts apart within seconds and reads as a
bug wherever two marks are visible together.

It never restarts. Each tick adds
`tick / cycleInterval` to a `phase` accumulator; when phase reaches 1 the pattern
advances by one and phase resets.

```swift
phase += DotMatrix.tick / cycleInterval
guard phase >= 1 else { return }
phase = 0
patternIndex = (patternIndex + 1) % DotMatrix.patterns.count
```

**Why an accumulator instead of a timer at the interval you want:** the interval
changes with microphone level, many times a second. Rebuilding the timer on every
change means it never survives long enough to fire, and the animation freezes
exactly when the user is talking. A fixed tick with a variable step has no such
failure mode.

## Speed follows the microphone

`DotMatrix.cycleInterval(for: level)` turns a 0...1 peak level into seconds per
pattern:

| input | level | interval | patterns/sec |
|---|---|---|---|
| silence | 0 | 6s | 0.17 |
| room noise (−40 dBFS) | 0.01 | 1.0s | 1 |
| speech (−20 dBFS) | 0.1 | 0.17s | 6 |
| loud (−10 dBFS) | 0.3 | 0.07s | 14 |

Two things make this feel right, and both are load-bearing:

- **dBFS, not raw amplitude.** Speech peaks around 0.1 on a 0...1 scale. A linear
  map spends 90% of its range on volumes a human never produces, so the icon
  barely moves while you talk.
- **Geometric interpolation** (`slowest * pow(fastest/slowest, level)`), so each
  step up in level is a constant *factor* faster rather than a constant amount.

Change the feel by editing `slowestCycle` / `fastestCycle` only. Leave the curve
alone unless you are prepared to re-check the table above.

## Two renderers, one source of truth

| where | how | why |
|---|---|---|
| window (`UttMark`) | SwiftUI `Canvas`, dots cross-fade | full control, animates smoothly |
| menu bar (`MenuBarIcon`) | `NSImage` redrawn per pattern, `Image` label | see below |

Sizes: 16pt in the menu bar and the collapsed pill, 17pt in the header, **51pt**
for the recording indicator — three times the header mark, which is what makes it
read as the app's activity indicator rather than a logo.

### The recording overlay

`Utt/Views/Activity/RecordingOverlay.swift` is where the indicator actually lives:
a borderless, non-activating, mouse-transparent `NSPanel` at `.statusBar` level,
centred on whichever screen the mouse is on. Recording happens inside somebody
else's app, so a mark drawn in utt's own window is a mark nobody sees.

It draws `UttMark` three times over a black `RadialGradient` that falls to clear
at the edges: the lit dots blurred wide, blurred tight, then crisp — the two blur
layers on `.plusLighter`, the lot in a `.compositingGroup()`. `litOnly: true` keeps
the dim cells out of the blur layers; blurring them smears grey over the black they
sit on.

#### Why it reads as lit

Four things, and dropping any one of them takes it back to looking painted:

- **Additive blending** (`.plusLighter`). Light adds; paint covers.
- **In linear space** (`.drawingGroup(colorMode: .extendedLinear)`). Summing sRGB
  values is summing the wrong numbers — overlapping halos go muddy and grey. This
  is the standard HDR-bloom pipeline's one non-negotiable step.
- **A dark surround.** Additive blending over a light background does nothing
  visible. That is the darkening's second job.
- **A smooth falloff, dithered.** The darkening is sampled off a smootherstep curve
  (`6t⁵-15t⁴+10t³`, zero first *and* second derivative at both ends) rather than
  hand-placed stops: every stop is a kink in the slope, and the eye finds a slope
  change far sooner than a value change — four stops read as concentric rings. What
  survives that is 8-bit banding, since a ramp this wide holds each of its 255 levels
  for tens of points. One level of noise added *last*, before the framebuffer rounds,
  turns each step into something the eye averages back out (`dither`). The noise lives
  in **alpha**, not colour: on a light background it is the alpha ramp that bands, and
  adding white to a transparent pixel changes nothing the compositor can see.
- **A white-hot core** (`hotCore`, in `UttMark.drawDot`). Real emitters saturate in
  the middle and only show their colour in the falloff, so each lit dot is a radial
  gradient from near-white to the tint, not a flat disc. The 16pt marks pass
  `hotCore: 0` — at that size the gradient is invisible and costs a gradient fill
  per dot.

#### Tuning it

Every number above lives in `~/Library/Application Support/dev.jurrejan.utt/overlay.json`
(`OverlayStyle` in UttCore). `just overlay-preview` pins the overlay on screen,
seeds the file with the current defaults, opens it, and reloads on every save —
`panelSize` is the one value that needs a relaunch. Keys decode independently, so a
partial or half-typed file still loads on its defaults rather than leaving you with
no indicator.

Without the recipe: `UTT_OVERLAY_DEBUG=1 …/utt.app/Contents/MacOS/utt`. Checking
this surface otherwise needs a human holding the hotkey.

**A `MenuBarExtra` label cannot use `Canvas`.** It draws nothing, the status item
collapses to zero width, and the icon silently disappears from the menu bar. Only
`Text` and `Image` are safe there. The menu bar path therefore renders each
pattern into an `NSImage` with `NSBezierPath` and hands over `Image(nsImage:)`.
Cost: no cross-fade, patterns step. That suits a dot matrix.

Both renderers share `DotMatrix.patterns`, `DotMatrix.cycleInterval`, and
`DotMatrix.rect(for:size:lit:)`. **Never fork any of the three** — a shape added
to one renderer and not the other is the bug this split exists to prevent.

### Geometry

`DotMatrix.rect(for:size:lit:)` is the only place dot positions are computed:

```swift
let step = size / 6                       // six columns across the full width
let radius = step * (lit ? 0.34 : 0.24)   // lit dots are bigger
x = step * (0.5 + col) - radius           // centre of the cell, not its corner
```

The `0.5` centres each dot in its cell, which is what makes the grid sit centred
in its frame. An earlier version used `size / 6.6` with a `0.45` offset and the
whole grid sat visibly high and left. If you change the divisor, change the offset
to match: **offset must be half the step, and the step must be `size / 6`.**

## Timer lifetime

The driver starts its timer on first access and never stops it. There is nothing
to gate on: the menu bar icon is on screen for the entire run, so any stop
condition is only ever a way to freeze the mark by accident. In particular do
**not** gate on `scenePhase` — a status item never reports an active scene.

Views own no timer state. They push `level` into the driver on `.onAppear` and
`.onChange(of: level)`, and react to `driver.patternIndex` for the cross-fade.

## Checklist for a change here

- [ ] Shape added to `DotMatrix.patterns` only, not to a renderer.
- [ ] Looks right at 16pt in the menu bar *and* 17pt in the window header.
- [ ] `just check` green.
- [ ] If you touched geometry: dots still centred (compare the menu bar icon to
      its neighbours — a mis-centred grid reads as "sitting high").
