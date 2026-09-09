# utt

> Native macOS on-device transcription — hold a hotkey, speak, release, text at the cursor

## What this is

utt replaces `python/utty`, which was a SwiftUI shell around a Python process. It
keeps utty's product and visual identity: all-native on-device transcription,
TCA, and a pure-logic SPM package that carries the parts worth testing.

Transcription is **Parakeet TDT v3 via FluidAudio** by default, with WhisperKit
alongside. Nothing leaves the machine.

## Mental model

```
Utt.xcodeproj        # generated — never edit, never commit changes by hand
project.yml          # XcodeGen source of truth for the project
Utt/
  App/               # @main, AppDelegate, lifecycle
  Clients/           # @DependencyClient wrappers around the system
    Api/             # http listener, routes, the settings it acts on
    Input/           # event tap, pasteboard
    Recording/       # capture, devices, idle suspension
    System/          # permissions, sleep, sounds, presence, updates
    Transcription/   # engine dispatch, Parakeet, Whisper
  Design/            # palette, typography, spacing, surfaces
  Features/          # TCA reducers: App, Transcription, Settings, History
  Views/             # SwiftUI, one directory per surface
  Resources/         # Info.plist, entitlements
UttCore/             # SPM package: pure logic + all the tests
raycast/             # Raycast extension — talks to the app through its JSON files
docs/                # hotkey semantics spec, phase 0 brief and results
```

The runtime path is: event tap → `KeyEventMonitorClient` (one serial
`AsyncStream`) → `AppFeature` → `HotKeyProcessor` → `TranscriptionFeature` →
`RecordingClient` → `TranscriptionClient` → `PasteboardClient`.

## Invariants

These are load-bearing. Each one exists because breaking it produced a real bug.

- **The signing identity is fixed.** `CODE_SIGN_IDENTITY` in `project.yml` is a
  hardcoded SHA-1, not a name — the Developer ID Application cert, in Debug and
  Release alike. TCC keys grants to the designated requirement, so a changed
  certificate silently resets Accessibility, Input Monitoring and Microphone.
  Ad-hoc signing (`-`) changes it on *every build*. The Developer ID requirement
  pins the team OU rather than a leaf hash, so renewing the cert keeps the grants
  — that is the one thing the old self-signed cert could not do. `just dr` prints
  the current requirement; `just verify-identity` refuses to build without the
  right cert.
- **One key event stream, one consumer.** A `Task` per key event can deliver
  release before press — independent tasks have no ordering guarantee.
- **`CaptureController` is not actor-isolated.** The audio tap runs on a
  real-time thread; inheriting main-actor isolation traps in
  `_swift_task_checkIsolatedSwift` on the first buffer.
- **`AVAudioPCMBuffer` and `CGEvent` never cross an isolation boundary.**
  Snapshot to values (peak, frame counts, keycode, flags) first.
- **Permission preflights lie on the first call.** `CGPreflight*Access` starts an
  asynchronous TCC lookup and answers "denied" until it lands. `AppFeature`
  requires two consecutive observations before reporting a permission missing.
  Warming the call up front does *not* help.
- **A tap created before Input Monitoring was granted stays dead forever.**
  `tapEnable` does nothing; only a full recreate revives it. Same after sleep.
- **Time enters through `@Dependency(\.date.now)`**, so hotkey tests scrub the
  clock instead of sleeping.
- **No App Sandbox.** Turning it on now would change the designated requirement
  and reset every TCC grant, and `StoragePaths` would start resolving into a
  container. Hardened Runtime is on, and
  `com.apple.security.device.audio-input` is required independently of the
  sandbox — without it the mic is denied outright, with no prompt and no TCC
  record.
- **No `LSUIElement`.** It made every launch start as an accessory, so
  double-clicking utt opened its window *behind* whatever was already on screen.
  The Dock icon is a runtime `setActivationPolicy` decision, and the login-item
  launch the key used to cover is detected through `launchIsDefaultUserInfoKey`
  instead.
- **Fronting the app goes through `AppActivation.front()`.** macOS 14 made
  activation cooperative: a bare `NSApp.activate()` only works if the active app
  yielded, which nothing does for a menu bar app, so it is a silent no-op and the
  window opens behind everything. `AppActivation` takes `ignoringOtherApps:` and
  falls back to LaunchServices; a SwiftLint rule fails the build on the bare call.
- **A model is named, never assumed.** `selectedModel` is a stored string read
  through `ModelCatalog.resolve(id:engine:)`, which falls back to the engine's
  recommendation — a settings file can name a model from an older build or from
  the *other* engine, and the alternative to falling back is an app that cannot
  transcribe until you edit JSON. The engine actors track what they loaded, or
  switching model keeps transcribing on the old weights.
- **Raycast talks to the app through Application Support, not a bridge.** The
  extension in `raycast/` reads `history.json` and `devices.json` and writes
  `microphonePriority` into `settings.json`; `@Shared(.fileStorage)` watches that
  file, so an external write reaches a running app with no relaunch. `devices.json`
  exists because a CoreAudio UID — the only stable way to name an input — cannot be
  obtained outside a CoreAudio client, and `SettingsFeature` already enumerates
  devices every 3 s.
- **The API's reach is enforced twice.** `ApiAccess` decides both what the
  listener binds to and which peers are accepted; "This Mac only" binds loopback
  so the port never appears on an interface, and the peer filter still runs.
  Everything, `/health` included, needs the bearer token, and an enabled API with
  an empty token yields no `ApiConfiguration` and therefore no listener.
- **The API card binds through the store, not `@Shared`.** Every other settings
  control writes the shared file directly, which reaches no reducer — fine for a
  value something reads later, useless for one that has to start a listener now.
  `SettingsFeature.apiChanged` is the only write path, and it is what mints the
  token on first switch-on.
- **A `utt://` caller must use `open -g`.** `utt://start|stop|toggle|cancel` reach
  `TranscriptionFeature` through `AppDelegate.application(_:open:)`. utt never
  activates itself there, but a plain `open` activates it for the caller — and the
  frontmost app when a recording *stops* is the app the transcript is pasted into,
  so a foregrounding caller dictates into utt's own window.
- **Suppression matches key *and* modifiers.** Suppressing a bare keycode would
  swallow ⌘V system-wide.
- **A release is any part of the chord coming up**, not the whole keyboard going
  quiet. Ctrl+P ends when either Ctrl or P is released. Something *extra* — a
  different key, a modifier the hotkey does not name — is an interruption, not a
  release, which is what keeps typing-while-dictating working.
- **`just check` must be green before a commit.** Zero warnings, `--strict` lint.

## Common change patterns

- **Add pure logic** → `UttCore/Sources/UttCore/`, with tests. Anything testable
  without a screen or a microphone belongs there.
- **Add a system capability** → a `@DependencyClient` struct in `Utt/Clients/`,
  `liveValue` forwarding to an actor (except the tap, which a C callback must be
  able to call synchronously).
- **Add UI** → a `View` in `Utt/Views/<surface>/`, reading `@Shared(.uttSettings)`
  directly rather than threading bindings through the store.
- **Add a setting** → property + `CodingKey` + one `decodeIfPresent` line in
  `UttSettings`, then a control in `Utt/Views/Settings/`. Every key decodes
  independently so an old file never fails to load.
- **Add a Raycast command** → a `.tsx` in `raycast/src/` plus an entry in
  `raycast/package.json`'s `commands`. Anything it needs to *read* from the app has
  to be a file in Application Support first (`raycast/src/utt.ts` is the only place
  that touches disk); anything it needs the app to *do* is a `utt://` verb.
- **Add an API endpoint** → one `case` in `ApiRoutes.respond`, one section in
  `docs/api.md`. Anything parsed before the token is checked belongs in
  `UttCore/Api/` with tests — that is the part a stranger can reach.
- **Add a `utt://` verb** → one `case` in `AppDelegate.action(for:)` and one line in
  the `CFBundleURLTypes` comment in `Info.plist`.
- **Add a model** → one entry in `ModelCatalog` (`UttCore`), plus the matching
  case in `ParakeetClient.version(for:)` if it is a Parakeet one. Whisper ids are
  folder names in `argmaxinc/whisperkit-coreml` and are passed through verbatim,
  so a typo fails at download time, not at compile time.
- **Redraw the app icon** → `just icon`. `tools/make-app-icon.py` draws
  `DotMatrix.patterns[0]` on `Palette.lcdGround` with `DotMatrix.rect`'s geometry
  and writes `Utt/Resources/AppIcon.icon`, an Icon Composer document — commit it,
  since the build reads that and not the script. It is *not* an appiconset on
  purpose: macOS 26 composites a legacy `.icns` onto its own light plate and
  shrinks it to fit, which reads as a grey border around the icon; a `.icon`
  supplies the background itself.
- **Child → parent in TCA** → pattern-match the child action in `AppFeature`
  (`case .transcription(.pasteFinished(let pasted)):`). No delegate-action
  ceremony.

## Verification

`just check` = `just-fmt-check` + `loc-check` + `dir-check` + `lint` + `build` +
`test` + `raycast-check`.

- `just run` — build, kill the running copy, launch
- `just dr` — print the designated requirement (TCC stability check)
- `just test` — `swift test` in `UttCore`
- `just loc-check` / `dir-check` — thresholds from `.quality.json` (300 warn /
  400 error lines, 6 files per directory)
- `just raycast-check` — `tsc --noEmit` + `bun test` in `raycast/`
- `just raycast-dev` — loads the extension into Raycast, reloads on save

Release: `just bump` → `just publish`, which runs `archive` → `export-app` →
`notarize` → `dmg` and then pushes the tag, creates the GitHub release from
`docs/RELEASE-X.Y.Z.md` with the dmg and the zip attached, and finally rewrites
and commits `appcast.xml`. `just dmg` is the shippable artifact — a
drag-to-Applications image, signed and notarized itself, because Gatekeeper
checks the container before anything is copied out of it.
`export-app` writes `release/ExportOptions.plist` itself; `notarize` needs the
`utt-notary` keychain profile, stored once with `xcrun notarytool
store-credentials` and an app-specific password.
`just sparkle-keys` once, and **back the private key up** — losing it means
installed copies can never be updated again.

The appcast is the load-bearing part:

- **`appcast.xml` at the repo root is the live feed.** `SUFeedURL` points at its
  `raw.githubusercontent.com` URL on `main`, so it is served for free and never
  moves. Deleting it, renaming the branch, or making the repo private strands
  every installed copy.
- **`release/appcast/` is not disposable.** `generate_appcast` carries the
  previous entries forward only from the appcast sitting next to the archives —
  generating into the wiped `release/export/` would publish a feed containing
  only the newest version.
- **The appcast is committed last.** It is the only thing installed copies read,
  so it must never name a download that is not attached to the release yet.
- **Deltas are off** (`--maximum-deltas 0`). A delta is a separate file that would
  have to be uploaded too, and an advertised delta that 404s fails the update.

## Versioning

Semver, and `just bump` is the only thing that writes it. It moves all three
together, behind `just check`, in one `release: X.Y.Z` commit:

- `MARKETING_VERSION` — what a person sees, and what names the dmg and the zip
- `CURRENT_PROJECT_VERSION` — a monotonic integer. Sparkle orders updates by it,
  so a reused build number is an update nobody is ever offered, on machines
  there is no other way to reach
- an annotated `vX.Y.Z` tag, `utt X.Y.Z` — what a shipped file is traced back to

A hook refuses hand-edits of either key; `.claude/scripts/guard_version_edit.py`
is the guard and carries its own test.

- `just next` — what the bump would decide, without deciding it
- `just bump` — read the part off the commits since the last tag
- `just bump major|minor|patch` — overrule it

The part follows the commit messages, which are conventional commits:

- **patch** — `fix:`, `perf:`, `refactor:`: nothing visible from outside changes
- **minor** — `feat:`: a new setting, a new `utt://` verb, a new engine or model
- **major** — `feat!:` or a `BREAKING CHANGE:` trailer: a removed `utt://` verb, a
  settings key that stops being read, a default that cannot be migrated

While the version is `0.x` a *derived* major lands as a minor — semver's own rule
for pre-1.0, where nothing is promised yet. Reaching 1.0.0 is a decision rather
than a consequence of a commit message, so it takes an explicit `just bump major`.

Bump first, then the release pipeline above: every artifact after this point is
named from `MARKETING_VERSION`. `docs/RELEASE-X.Y.Z.md` is written by hand and
`bump` only warns when it is missing — what changed and why is prose, not
something a script should be inventing.

## Known gaps

- The disk image has no custom window background or icon layout — the volume
  opens in plain icon view with `utt.app` and the `Applications` alias in it.
  Positioning them takes Finder AppleScript; it has not been worth it.
- Deferred by decision, not oversight: caret-tracking indicator, LLM staging
  panel, log viewer, setup wizard, OpenAI/LAN providers, history audio playback,
  left/right modifier sides.

## Related context

- [agent.md](agent.md) — verify loop, auto-fix commands, boundaries
- [docs/api.md](docs/api.md) — the HTTP API: reach, auth, endpoints
- [docs/hotkey-semantics.md](docs/hotkey-semantics.md) — the press/hold/double-tap
  spec the `HotKeyProcessor` tests are written against
- [docs/phase0-results.md](docs/phase0-results.md) — what the spike actually
  proved about taps, TCC and FluidAudio's API surface
- `.quality.json` — loc / dir thresholds (single source of truth)

<!-- agent-log:policy -->
### Shared agent journal

Use `./agent-log` (a shim for `atlas agent-log` — both are identical) for short-lived
operational awareness between concurrent agents. It is not chat and not a task tracker: the
issue tracker remains the source of truth for ownership, blockers, and durable findings.

- Run `./agent-log recent` before interpreting shared state.
- Before an action that can change another agent's observations, write an intent with every
  affected scope. This includes shared-worktree edits, generated artifacts, git/index
  mutations, and shared ports, processes, or services.
- Run builds, tests, and deployments through the wrapper so start, commit, dirty state,
  duration, exit code, and outcome are recorded even on failure:
  `./agent-log run build|test|deploy --scope <resource> [--bead <id>] -- <command...>`.
- For manual operations, use `./agent-log begin <operation> --scope <resource> [--bead <id>]
  -- <summary>` and always close the returned id with `./agent-log end <id> --outcome
  ok|failed|cancelled -- <result>`. `<operation>` is one of build, commit, deploy, edit, implement, investigate, merge, push, review, sync, test — what
  makes this particular run specific goes in the summary, never in an invented operation name.
- Record a temporary result-affecting discovery with `./agent-log finding --scope <resource>
  --evidence <fact> [--bead <id>] -- <summary>`. This is the entry that saves another agent a
  wasted run, and the one most often skipped — write one whenever you learn something that
  would change what a concurrent agent does next, especially a dead end. Promote lasting
  knowledge to the issue tracker or the relevant doc.
- At session end, write `./agent-log handoff -- <stopping point + next step>` — the durable
  baton the next session's briefing picks up. Handoffs never expire; the latest one is
  always shown by `recent`.
- Intents expire after 20 minutes and findings after 4 hours unless `--ttl` overrides them.
  Renew by closing and reopening an intent; never treat an expired entry as current.
- Keep summaries factual and short. Do not reply, ask questions, mention agents, narrate
  routine progress, or log isolated reads/edits/tests that cannot affect anyone else.

Canonical scopes are `path:<repo-relative-path>`, `artifact:<name>`, `service:<name>`,
`host:<name>`, `port:<number>`, and `git:<worktree-or-ref>`; a repo may define additional
canonical scopes of its own. Add multiple `--scope` flags when needed. The journal SQLite db
lives in the git common directory, so linked worktrees share it without dirtying the repo.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
