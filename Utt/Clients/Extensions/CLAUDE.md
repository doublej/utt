# Extensions

## What this is

Everything about a third-party extension while utt is running — discovery,
capability negotiation, and the log of what utt did about it.
`UttCore/Sources/UttCore/Extensions/` (see its `CLAUDE.md`) owns the manifest
model and its sanitisation; this folder owns the running system.

## Invariants

- **A capability an extension declares has to survive `sanitized()`.** It
  rebuilds the manifest field by field, so a new flag not passed through there
  decodes fine, tests fine, and is silently false by the time any lane reads it.
  `ExtensionCapabilityTests` is what catches it.
- **Everything utt decides about an extension goes through `ExtensionLog`** —
  refused keys, failed clips, silent filters. `os_log` alone is invisible
  (`log show` cannot open the store from an ordinary shell). The log is
  in-memory, newest first, read by the pages; a repeated line is counted on one
  entry and only its first occurrence is mirrored to the unified log, because
  the manifest scan runs three times a second. Nothing is persisted.
- **A path a manifest names is revealed, never opened.** `daemon.log` reaches
  the Finder through `activateFileViewerSelecting`. `NSWorkspace.open` lets
  LaunchServices pick an app by extension, so a manifest naming a `.command`
  would turn "drop a file in a folder" into "run this as the user".
- **A crash-looping daemon is not a stopped one.** A job dying on something
  permanent has a pid about a second in every ten, so read `LastExitStatus`
  from `launchctl list`, not the pid. `.stopped` says "Restart starts it";
  `.failing` says read the log.

## Common change patterns

- **Say something about an extension** → `ExtensionLog.note` or `.problem`,
  with the extension's id, or nil for a manifest utt could not attribute (read
  on the Extensions page). Never a bare `Logger` here.
