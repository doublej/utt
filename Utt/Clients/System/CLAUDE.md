# System

## What this is

Permissions, sleep, sounds, presence, updates — the TCC and lifecycle surface.

## Invariants

- **Permission preflights lie on the first call.** `CGPreflight*Access` starts
  an asynchronous TCC lookup and answers "denied" until it lands. `AppFeature`
  requires two consecutive observations before reporting a permission missing.
  Warming the call up front does *not* help. (This is why a tap built too early
  stays dead — see `Utt/Clients/Input/CLAUDE.md`.)
- **No App Sandbox.** Turning it on now would change the designated requirement
  and reset every TCC grant, and `StoragePaths` would start resolving into a
  container. Hardened Runtime is on, and
  `com.apple.security.device.audio-input` is required independently of the
  sandbox — without it the mic is denied outright, with no prompt and no TCC
  record.

## Related context

- `Utt/Clients/Input/CLAUDE.md` — the tap that a lagging preflight can leave
  dead
- root `CLAUDE.md` — the signing identity that TCC grants are keyed to
