# Input

## What this is

The event tap and the pasteboard. `KeyEventMonitorClient` turns raw `CGEvent`s
into one serial stream (runtime path: `docs/architecture.md`); `HotKeyProcessor` in
`UttCore/Sources/UttCore/Logic/` turns it into press/hold/double-tap decisions.

## Invariants

- **One key event stream, one consumer.** A `Task` per key event can deliver
  release before press — independent tasks have no ordering guarantee.
  `KeyEventMonitorClient` is the single serial `AsyncStream`; do not fan events
  out into per-event tasks.
- **A tap created before Input Monitoring was granted stays dead forever.**
  `tapEnable` does nothing; only a full recreate revives it. Same after sleep.
  (System's permission preflight lags — see `Utt/Clients/System/CLAUDE.md` — so
  a tap can be built while the grant is still in flight.)
- **`CGEvent` never crosses an isolation boundary as itself** — see
  `.claude/rules/isolation-boundaries.md`.
- **Suppression matches key *and* modifiers.** Suppressing a bare keycode would
  swallow ⌘V system-wide.
- **A release is any part of the chord coming up**, not the whole keyboard going
  quiet. Ctrl+P ends when either Ctrl or P is released. Something *extra* — a
  different key, a modifier the hotkey does not name — is an interruption, not a
  release, which is what keeps typing-while-dictating working.
- **Time enters through `@Dependency(\.date.now)`**, so hotkey tests scrub the
  clock instead of sleeping.

## Verification

`swift test` in `UttCore` covers `HotKeyProcessor` against
`docs/hotkey-semantics.md`, the press/hold/double-tap spec.
