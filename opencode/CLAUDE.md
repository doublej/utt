# opencode

OpenCode CLI plugin: `ctrl+s` dictates into the prompt through utt. OpenCode draws
the dictation (meter, live words, transcript); utt shows and pastes nothing.
User-facing contract and file table: `README.md`.

## Layout

- `tui.ts` — entry. OpenCode loads a local plugin directory from `<dir>/tui.ts`, not
  from `package.json` exports, so it stays at the root.
- `src/tui.tsx` — wiring only: commands, the approval detour, the Esc/Enter
  layer, the footer and meter, the poll timer.
- `src/dictation.ts` — the state machine (`idle → recording → finishing`), pure,
  driven by injected deps.
- `src/region.ts` — the stretch of the prompt one dictation owns.
- `src/meter.ts` — level → segments, on utt's dB scale and zones.
- `src/shade.ts` — the not-final style on the live words.
- `src/utt.ts` — the only file that touches disk or runs `open`.

## Invariants

- **The dictation is utt's to hand over (`ownsDictation`, `utt://start?for=opencode`).**
  The first `opencode.level.json` write is the proof; until one arrives the plugin
  never touches the prompt, because utt is then pasting the text itself. The utt
  side is `UttCore/.../Extensions/Dictation/` and `TranscriptionFeature+Lanes.swift`.
- **Every handed-over dictation ends in one transcript write** (`""` for nothing),
  so `finishing` ends on a file, not a timer. The 30 s wait only covers utt dying.
- **No key ever waits on utt.** Dictate during `finishing` starts the next take
  (utt drops a transcription in flight when a recording starts); Esc sends
  `utt://cancel`. The one exception is deliberate: Enter is held while a
  dictation is open, so a prompt never goes out with live words in it.
- **The footer is replaced (`replace: "prompt.footer"`) only while a dictation is
  open**, claimed on the way in and released on the way out. A replacement
  suppresses every claim under it, other plugins' included.
- **Live words are shaded with an extmark, never a bare highlight.** The textarea
  rebuilds all highlights from its extmarks on every change. Every road to
  `idle`, and every landing, takes the shade down first.
- **utt is reached only through its extension files and `utt://` verbs**, opened with
  `open -g` — except `utt://show`, which must front utt and is never sent
  mid-dictation. Never utt's `settings.json`, never `consent.json` writes.
- **The region only edits text it can prove is its own** (`Region.intact`); an
  edited-away region sends the transcript to the cursor instead.
- **The region is placed on the first tick, not at the key.** From the palette the
  palette's field still has focus when the command runs.
- **The log (`~/Library/Logs/utt-opencode.log`) never holds the words**, only events
  and lengths.
- **`@opentui/*`, `solid-js` and `@opencode/*` are dev dependencies for types
  only, and optional peers in the published package.** OpenCode supplies them at
  runtime; a second solid-js breaks reactivity. Never move them to `dependencies`.
- **Published to npm as `utt-opencode`** (`opencode plugin add utt-opencode`).
  OpenCode runs the TypeScript source as is, so there is no build step; `files`
  ships `tui.ts`, `src/` and the README, never `tests/`.
- **Relies on unexported OpenCode behaviour:** `currentFocusedEditor` being the
  prompt textarea (with `extmarks` and `syntaxStyle`), the `prompt.clear` command
  id, and Enter being bound to `return`. Re-test after upgrades.

## Commands

```bash
bun install
just opencode-check
```
