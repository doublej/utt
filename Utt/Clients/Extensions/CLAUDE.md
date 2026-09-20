# Extensions

## What this is

Everything about a third-party extension while utt is running — discovery,
capability negotiation, and the log of what utt did about it.
`UttCore/Sources/UttCore/Extensions/` (see its `CLAUDE.md`) owns the manifest
model and its sanitisation; this folder owns the running system.

## Invariants

- **A capability an extension declares has to survive `sanitized()`.** It
  rebuilds the manifest field by field, so a new flag that is not passed
  through there decodes fine, tests fine, and is silently false by the time any
  lane reads it. `ExtensionCapabilityTests` is what catches it.
- **Everything utt decides about an extension goes through `ExtensionLog`.** A
  refused key, a clip that failed, a filter that never answered: in `os_log`
  alone they were invisible — `log show` cannot open the store from an ordinary
  shell — so an extension that did nothing looked the same as one utt had
  thrown out. The book keeps them in memory, newest first, and the pages read
  it. A line said again is the same entry counted rather than a new one, and
  only the first of them is mirrored to the unified log: the manifest scan runs
  three times a second. Nothing is persisted — a standing problem says itself
  again within three seconds of the next launch.
- **A path a manifest names is revealed, never opened.** `daemon.log` reaches
  the Finder through `activateFileViewerSelecting`. `NSWorkspace.open` is
  LaunchServices picking an app by extension, so a manifest naming a `.command`
  would turn "drop a file in a folder" into "run this as the user".
- **A crash-looping daemon is not a stopped one.** `launchctl list` reports
  `LastExitStatus` beside the pid, and a job dying on something permanent has a
  pid for about a second in every ten — so the pid a poll catches is luck and
  the exit status is the stable half. `.stopped` says "Restart starts it";
  `.failing` says read the log, because Restart is the button that gets
  pressed twenty times.

## Common change patterns

- **Say something about an extension** → `ExtensionLog.note` or `.problem`,
  with the extension's id, or nil for a manifest utt could not attribute —
  that one has no page of its own and is read on the Extensions page. Never a
  bare `Logger` here.

## Related context

- `UttCore/Sources/UttCore/Extensions/CLAUDE.md` — the manifest model and
  `sanitized()`
