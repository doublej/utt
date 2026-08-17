# Text pipeline + delivery confirmation — build plan

## Why

The Text tab today is four cards of checkboxes and a flat list of literal
find/replace pairs. Everything in it is *blind*: you cannot see what a rule does
until you dictate, you cannot reorder rules even though order is load-bearing,
and the transcript lands in someone else's document with no chance to look at it
first and no way to take it back.

Two things fix that, and they are the whole scope:

1. **A delivery confirmation surface** — utt stops being fire-and-forget.
2. **A rule bench** — the Text tab stops being blind.

Everything else on the idea list (per-app profiles, streaming partials, LLM
cleanup) is deliberately out of scope. Per-app profiles are a config feature that
does not fix the trust problem; streaming partials do not fit a file-based
Parakeet path.

---

## Phase 1 — UttCore (pure logic, tested)

**1.1 `DeliveryMode`** — new file
`UttCore/Sources/UttCore/Settings/DeliveryMode.swift`

```swift
public enum DeliveryMode: String, Codable, CaseIterable, Sendable {
    case immediate   // today's behaviour: paste, then show what was pasted
    case review      // hold the transcript, paste on confirm
}
```

**1.2 `WordRemappingApplier.matches(_:in:)`** — extend
`UttCore/Sources/UttCore/Text/WordRemapping.swift`

Factor the existing `(?<!\w)…(?!\w)` pattern construction out of `apply` into a
private `pattern(for:)`, then add:

```swift
public static func matches(_ remapping: WordRemapping, in text: String) -> Bool
```

The bench needs to say "this rule fires / does not fire" against a sample. Reuse
the pattern builder — do not re-derive the escaping, it is the one place the
word-boundary semantics live.

**1.3 `RulePresets`** — new file
`UttCore/Sources/UttCore/Text/RulePresets.swift`

A preset `[WordRemapping]` the user can seed the list with in one click. This is
the single most-missed dictation feature and it costs one array:

| said | written |
|---|---|
| new line | `\n` |
| new paragraph | `\n\n` |
| comma | `,` |
| period / full stop | `.` |
| question mark | `?` |
| exclamation mark | `!` |
| colon | `:` |
| semicolon | `;` |
| open paren / close paren | `(` `)` |
| open quote / close quote | `"` |
| dash | `—` |

Expose `RulePresets.punctuation` returning fresh `WordRemapping` values (fresh
`UUID`s each call — they get appended to the user's array).

Seeding appends only the rules whose `match` is not already present, so pressing
the button twice does not duplicate the list.

**1.4 Settings** — `UttCore/Sources/UttCore/Settings/UttSettings.swift`

Three new properties, each with a `CodingKey` and one `decodeIfPresent` line in
`decodeModelAndOutput` (or a new `decodeDelivery` if that function gets long):

```swift
public var deliveryMode: DeliveryMode = .immediate
public var showTranscriptHUD: Bool = true
public var hudDismissAfter: Double = 6      // seconds; 0 = stay until dismissed
```

`useClipboardPaste == false` and `deliveryMode == .review` is a contradiction
(review's whole job is to gate a paste). Normalize on decode the way
`normalizeDoubleTapSettings` does: if `!useClipboardPaste`, force
`deliveryMode = .immediate`.

**1.5 Tests** — `UttCore/Tests/UttCoreTests/`

- `RulePresets.punctuation` seeding is idempotent.
- `matches` respects word boundaries (`silly` does not fire inside `silliness`).
- `applyTextTransforms` with the preset turns "hello comma world new line bye"
  into "hello, world\nbye".
- `DeliveryMode` decodes from an older settings file (absent key → `.immediate`).

Watch the directory cap: `Text/` is at 3 files, `Settings/` at 5. Both have room.

---

## Phase 2 — Delivery state machine

**2.1 `PasteboardClient.undo()`** — `Utt/Clients/Input/PasteboardClient.swift`

Post ⌘Z through the existing synthetic path. `postCommandV` already builds the
event, sets `.maskCommand`, marks it with `SyntheticKeyEvent.mark` and posts to
`.cgSessionEventTap` — generalise it to `postCommand(_ keyCode: CGKeyCode)` and
add `undo` calling it with `6` (Z).

This is best-effort by nature — same caveat as paste, `CGEvent.post` has no
delivery acknowledgement, and an app with no undo stack will ignore it. Say so in
the doc comment; do not pretend it is guaranteed.

**2.2 `TranscriptionFeature`** — split, do not grow

`Utt/Features/Transcription/TranscriptionFeature.swift` is 215 lines and the cap
is 400 with a warning at 300. Put the new work in
`Utt/Features/Transcription/TranscriptionFeature+Review.swift`.

State gains:

```swift
/// The transcript waiting on the user, in `.review` mode.
var pendingReview: String?
/// What the last delivery went into, captured at stop time — not at paste time,
/// because the HUD may be on screen by then.
var deliveryTarget: AppIdentity?
/// Drives the HUD's post-delivery card.
var lastDeliveredAt: Date?
```

Actions gain: `reviewAccepted`, `reviewDiscarded`, `undoLastPaste`,
`hudDismissed`, `hudTimerExpired`.

`transcribed(_:_:)` branches:

- `.immediate` → paste as today, then start the HUD dismiss timer.
- `.review` → set `pendingReview`, do **not** paste, arm key suppression, no timer
  (a review card that vanishes on its own is worse than none).

`reviewAccepted` pastes `pendingReview`, clears it, releases suppression, starts
the dismiss timer. `reviewDiscarded` clears it and releases suppression.

Every path that clears `pendingReview` must release suppression. Route them
through one `endReview(&state)` helper — a leaked suppression means the user's
Return key is dead system-wide, which is the worst bug this feature can ship.

**2.3 Dismiss timer** — a `.run` with `Task.sleep(for: .seconds(settings.hudDismissAfter))`
sending `.hudTimerExpired`, `.cancellable(id: CancelID.hud, cancelInFlight: true)`.
Skip entirely when `hudDismissAfter <= 0`. Cancel on any user interaction with
the HUD.

**2.4 History timing** — `Utt/Features/App/AppFeature.swift`

`recordHistory` currently hangs off `.transcription(.pasteFinished)`. In `.review`
mode a discarded transcript must **not** land in history — it was never delivered.
Record on the accepted path only. Keep `frontmostApp()` capture as-is.

**2.5 Key routing** — `Utt/Features/App/AppFeature.swift`

`KeyEventMonitorClient.setSuppressed([HotKey])` is already dynamic and already the
right mechanism, so no client change is needed. While `pendingReview != nil`,
suppress bare Return and bare Escape and map them in the hotkey handling path to
`.transcription(.reviewAccepted)` / `.reviewDiscarded`.

Two invariants to respect:
- The existing hotkey chord stays suppressed at the same time — merge the arrays,
  never replace them.
- The suppression list must be restored the moment review ends. Derive it from
  state in one place rather than toggling it from two call sites.

---

## Phase 3 — The HUD

New directory `Utt/Views/Review/` (`Utt/Views/Settings/` is already at the
six-file cap; do not add there).

**3.1 `TranscriptHUD.swift`** — the panel

Copy the panel setup from `Utt/Views/Activity/RecordingOverlay.swift`, which
already solved this exact problem: `.borderless, .nonactivatingPanel`,
`isFloatingPanel`, `level = .statusBar`, `collectionBehavior` of
`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`,
`hidesOnDeactivate = false`.

Differences from the recording overlay:

- **`ignoresMouseEvents = false`** — the HUD has buttons. The recording overlay is
  click-through; this one is not.
- **It must still never become key.** `.nonactivatingPanel` plus never calling
  `makeKey` covers it. utt pastes into whatever is frontmost; a HUD that takes
  focus breaks the one thing the app does. This is the load-bearing constraint of
  the whole phase.
- **Bottom-centre of the active screen**, sitting above the Dock — use
  `screen.visibleFrame`, not `frame`. Same "screen the mouse is on" rule as the
  overlay, re-evaluated each time the HUD appears.

Ordered front for the run, drawing nothing when there is nothing to show — same
trick the overlay uses, so panel visibility stays a SwiftUI decision.

**3.2 `TranscriptHUDView.swift`** — the content

Four states, one card, `chromeGlass` in a rounded rect so it matches the pill:

| state | shows |
|---|---|
| recording | level bar + `ElapsedTimer` + "Listening" |
| transcribing | spinner + "Transcribing…" |
| review (`.review` mode) | the text, target app name, `⏎ Paste` · `esc Discard` · `Add rule` |
| delivered (`.immediate`) | the text, "→ Slack", `Undo` · `Copy` · `Add rule`, fading on the timer |

Reuse `CompactVuMeter`, `ElapsedTimer`, `Card`/`chromeGlass`, `Typography`,
`Palette`, `Spacing`. Do not invent a second visual language, and do not touch the
recording overlay's render — its geometry, dithering and falloff are tuned.

Text is truncated to a few lines with the full transcript on hover; a long
dictation must not produce a HUD that covers the screen.

`Add rule` opens the main window on the Text tab with a blank replacement row
appended, prefilled with the selected/last word if that is cheap — if it is not,
just append an empty row. Do not build a text-selection mechanism for it.

**3.3 Wiring** — `Utt/Views/App/AppRootView.swift` (or wherever `RecordingOverlay`
is constructed) instantiates the HUD alongside it, gated on
`settings.showTranscriptHUD`.

---

## Phase 4 — The Text tab

`Utt/Views/Settings/` is at six files. Move `TextSettings.swift` into a new
`Utt/Views/Settings/Text/` and split there. That drops the parent to five and
gives the new work its own directory.

**4.1 `Text/TextSettings.swift`** — the composed tab, cards in this order:
Delivery → Rule bench → Formatting → Replacements → History.

**4.2 Delivery card** gains:

- A segmented picker: **Paste immediately** / **Review first**, with a one-line
  explanation under it ("Review first: the transcript waits in a panel; ⏎ pastes
  it, esc throws it away").
- "Show the transcript panel" toggle + a dismiss-delay stepper, disabled and
  forced on when the mode is `.review` (a review mode with no panel is a black
  hole).
- Disable the mode picker entirely when `useClipboardPaste` is off, with the
  reason in `.help` — matching the `normalizeDoubleTapSettings` precedent of the
  UI enforcing what decode also enforces.

**4.3 `Text/RuleBench.swift`** — the thing that makes this tab a tool

A `TextEditor` seeded with the last transcript from `@Shared(.uttHistory)` (button:
"Use last transcript"; falls back to a canned sample sentence when history is
empty), and directly under it the live output of
`settings.applyTextTransforms(to: sample)` in the mono face.

It updates as you type in the box *and* as you edit any rule or toggle — that
second half is the point. Changing "Remove punctuation" and watching the output
change is the entire feature.

**4.4 `Text/ReplacementList.swift`** — extract `RemappingRow` here and add:

- **Drag to reorder** (`.onMove` on the `ForEach`). Order already matters —
  `WordRemappingApplier` documents that a later rule can rewrite an earlier one's
  output — and today the UI cannot express it. This is a real bug, not a nicety.
- **A hit dot per row**: filled when `WordRemappingApplier.matches` is true against
  the bench sample, hollow when not. Instant feedback on why a rule is not firing.
- **"Add spoken punctuation"** button seeding `RulePresets.punctuation`.
- Keep the existing per-rule enable checkbox and delete button.

---

## Phase 5 — Gates

1. `just check` green — `just-fmt-check`, `loc-check`, `dir-check`, `lint`
   (`--strict`, zero warnings), `build`, `test`. Fix and rerun; three failures on
   the same thing means change approach and say so.
2. Watch the two caps continuously, not at the end: **400 lines per file**,
   **6 files per directory**.
3. `just install-app` — replaces `/Applications/utt.app` and launches it.
4. Report what was verified by running it versus what was only compiled. The
   HUD's non-activating behaviour and the Return/Escape suppression cannot be
   proven by a unit test; say plainly whether they were exercised by hand.

---

## Amendments (found during review — all verified in source)

These three are not optional extras; without them the feature has holes in it.

**A1. Keep the raw transcript.**
`TranscriptionFeature.transcribed` computes `let text = settings.applyTextTransforms(to: raw)`
and only `text` survives — `raw` is dropped on the floor. So the HUD's `Undo`
and `Add rule` have nothing to fall back *to*, and the bench cannot recompute
against a real past transcript.

Add `public var rawText: String?` to `Transcript`
(`UttCore/Sources/UttCore/Models/TranscriptionHistory.swift`) — optional, with a
`decodeIfPresent`, so existing history files still load. Thread it through
`.pasteFinished` → `AppFeature.recordHistory` → `HistoryFeature.record`. Store it
on `TranscriptionFeature.State` alongside `lastTranscript`.

The bench's "Use last transcript" should seed from `rawText` when present — the
whole point is to run the pipeline over it, and seeding from already-transformed
text would apply every rule twice.

**A2. Close the blind window.**
`RecordingOverlayView.body` renders `if recording || OverlayStyleStore.isPreviewing`,
and `recording` is `status == .recording`. From key release until inference
returns (0.3–3s on Parakeet) the overlay is gone and the HUD has not appeared:
the screen is simply empty at the exact moment the user is waiting to find out
whether it worked.

Change the condition to cover `.transcribing` as well, and hold the darkening
through it. Drive the mark from an indeterminate cycle on the existing
`DotMatrixDriver` rather than `meterLevel` (which is 0 by then — `stop` zeroes it).

**Do not retune the render.** Geometry, falloff, halo, dither and the
`overlay.json` numbers stay exactly as they are. This is a change to *when* the
overlay is on screen and what drives the mark, nothing else.

**A3. The HUD must show failures, not only successes.**
`.failed(...)` on the transcription status renders in exactly two places —
`AppRootView.swift:64` and `MenuBarContent.swift` — both invisible while the user
is dictating into Slack. The two worst outcomes are currently silent:

- `"Nothing heard — your input level looks very low"`
- `"Couldn't paste — the text is on your clipboard"` ← this one silently loses
  text the user believes was delivered.

Give both the HUD, 4s auto-dismiss. The paste-failure card must say the text is
on the clipboard and offer `Copy` again. These are the only HUD states that
need a sentence rather than a label.

**A4. Bench ordering note (surface, do not "fix").**
`applyTextTransforms` runs removals → remappings → formatting, so "Lowercase
everything" flattens the capitals a replacement just produced (`Claude Code` →
`claude code`). The bench will make this obvious. Leave the order alone — it is
documented and deliberate — but when `lowercaseTranscripts` is on AND any enabled
rule's replacement contains an uppercase character, show a one-line note under
the bench output saying formatting runs last. Do not reorder the pipeline.

**A5. Capture `frontmostApp` before the paste, not after.**
`AppFeature.recordHistory` calls `pasteboard.frontmostApp()` *after* the paste has
landed. Move the capture into `TranscriptionFeature.finished` (recording stop) and
carry it on state. Already required by the HUD, which needs the target app name;
this just makes it correct rather than incidentally-right.

**B1. The two Delivery checkboxes are dead. Fix them first.**

`useClipboardPaste` and `copyToClipboard` appear in exactly two places each —
the property/CodingKey in `UttSettings.swift` and the `Toggle` in
`TextSettings.swift`. **Nothing in the delivery path reads either one.**
`transcribed` calls `pasteboard.paste(text)` unconditionally, and
`PasteboardActor.paste` always restores the previous clipboard.

So today: unchecking "Paste at the cursor" still pastes. Checking "Leave the
transcript on the clipboard" still restores your old clipboard. Both controls at
the top of the tab are lies.

This outranks everything else in this document. Wire them:
- `useClipboardPaste == false` → copy only, never post ⌘V. The HUD becomes the
  entire feedback channel in that mode.
- `copyToClipboard == true` → skip the restore in `PasteboardActor.paste`.
  Thread it as a parameter; do not read settings from inside the actor.

**B2. `.failed` never clears.** The only routes back to `.idle` are `start`,
`cancel`, and a successful transcript, so a failure sticks in the banner and the
menu-bar status line forever. Give it the same auto-dismiss timer as the HUD.

**B3. Turning off "Keep past transcripts" silently breaks ⌥⇧V.**
`AppFeature.withLastTranscript` reads `transcripts.history.first?.text`, and
`HistoryFeature.record` early-returns when `saveTranscriptionHistory` is false.
So that one checkbox also disables both menu-bar items and the global
paste-last hotkey, with no hint anywhere.

Fall back to `state.transcription.lastTranscript` when history is empty. The
existing doc comment already claims it "falls back to history" — make the
fallback go the other way too.

**B4. A discarded review must not vanish.** History is written only from
`.transcription(.pasteFinished)`, so in `.review` mode both `esc` and a hotkey
re-press drop the transcript permanently. Keep `lastTranscript` set on the
discard path so ⌥⇧V can still recover it. "Review first" must not be the mode
that loses your dictation.

**B5. Guard `Undo`.** ⌘Z is fire-and-forget like ⌘V, and if the user has typed
since the paste it undoes *that* instead. Only offer the button while
`pasteboard.frontmostApp()` still matches the app we pasted into; hide it
otherwise. Hide it always when the paste failed.

**B6. More silent failures for the HUD:**
- `recordingFinished(nil)` returns to idle showing nothing at all.
- Empty transcript + `quietWarning` has no text, so the HUD needs a distinct
  no-text layout — Undo, Copy and Add-rule are all meaningless there.
- First-run ANE compile stalls ~27s under the label "Processing". Say
  "Preparing model" when the model is not yet ready.

**B7. Free signal:** `ParakeetClient.Transcript.confidence` is computed on every
transcription and then only logged — `TranscriptionClient.transcribe` returns
`result.text` alone. Plumb it through and let the HUD show a quiet low-confidence
hint. Two lines. Do not build a UI around it beyond that.

### REVISED: how the review keys work

**The original plan said to suppress bare Return and Escape. Do not do that.**
It walks straight into the invariant it was supposed to respect — CLAUDE.md says
suppressing a bare keycode swallows it system-wide, and bare Return being dead in
the frontmost app for the panel's whole lifetime is exactly that bug. A panel that
fails to dismiss leaves the Mac with no Return key.

Instead:

- **Mouse:** the HUD's buttons work by click. A `.nonactivatingPanel` handles
  clicks without activating utt, so this costs nothing and needs no suppression.
- **Keyboard:** bind review to *modified* chords — `⌘⏎` to paste, `⌘⌫` to
  discard. These satisfy the "key *and* modifiers" rule, are safe to suppress,
  and merge into the existing array alongside `settings.hotkey` and
  `pasteLastHotKey`.
- Note that `setSuppressed` is called from exactly one place
  (`AppFeature.swift:272`, with `[settings.hotkey, Self.pasteLastHotKey]`), and
  any `.settings(.binding)` resync calls it again. So the review chords **must**
  be part of what that one call site computes from state — a transient
  suppression set anywhere else gets clobbered the next time settings change.
  This is why the plan says derive it in one place.
- Label the chords on the HUD so they are discoverable.

Hotkey re-press while the HUD is up: in `.immediate` mode the HUD just vanishes
and recording starts. In `.review` mode, treat it as discard-and-record, and B4
keeps the text recoverable.

### Considered and deliberately not in scope

- **Replacement match modes** (substring / regex / case-preserving). Real gap —
  `api → API` can never survive `apis` today — but it is a schema change to
  `WordRemapping` plus a column in every row, and the bench will tell us what is
  actually needed. Revisit after.
- ~~**Editable filler list.**~~ Done after the fact: `WordRemoval` is gone and a
  filler is an ordinary rule with an empty replacement, seeded from
  `RulePresets.fillers`. Phrases (*you know, I mean*) work because the match is
  literal, so they are the user's to add.
- **On-device polish pass via `FoundationModels`.** macOS 26 is already the
  deployment target, so it is available with no download and no network — privacy
  holds. Genuinely the next big idea. Out of scope here because it is an LLM
  feature nobody asked for yet, and CLAUDE.md lists the LLM staging panel as
  deferred by decision.

---

## Invariants this must not break

From `CLAUDE.md`, all of them earned by a real bug:

- **The HUD never takes focus.** Non-activating, never key. utt pastes into the
  frontmost app.
- **Suppression matches key *and* modifiers**, and must be released the instant
  review ends. A stuck Return suppression breaks the whole machine.
- **One key event stream, one consumer.** Route the HUD's keys through the
  existing stream; do not add a second monitor.
- **Every settings key decodes independently** so an old file still loads.
- **Do not edit `Utt.xcodeproj`** — `project.yml` is the source, `just generate`
  regenerates. New files under existing source roots are picked up automatically.
- **Do not touch `RecordingOverlay`'s render.**
