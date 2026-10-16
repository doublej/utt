# utt

> Native macOS on-device transcription — hold a hotkey, speak, release, text at the cursor

## What this is

All-native on-device transcription: TCA app plus a pure-logic SPM package that
carries the parts worth testing. **Parakeet TDT v3 via FluidAudio** by default,
WhisperKit alongside. Nothing leaves the machine.

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
    App/             # root view, AppSection (the rail's sections), route
    Chrome/          # AppRail, OnboardingRail, PageHeader, the pill
    Settings/        # SettingRow + SettingsGroup, one page per section in
                     #   Dictation/, Text/, Output/, Application/
  Resources/         # Info.plist, entitlements
UttCore/             # SPM package: pure logic + all the tests
raycast/             # Raycast extension — talks to the app through its JSON files
docs/                # specs (hotkeys, API, cleanup), phase 0, release notes
```

Runtime path: event tap → `KeyEventMonitorClient` (one serial `AsyncStream`) →
`AppFeature` → `HotKeyProcessor` → `TranscriptionFeature` → `RecordingClient` →
`TranscriptionClient` → `PasteboardClient`.

## Invariants

Folder-specific invariants live in the nested `CLAUDE.md` files below. Global:

- **The signing identity is fixed.** `CODE_SIGN_IDENTITY` in `project.yml` is the
  Developer ID Application cert's SHA-1, Debug and Release alike. TCC keys grants
  to the designated requirement, so another cert (or ad-hoc `-`, which changes it
  every build) silently resets Accessibility, Input Monitoring and Microphone.
  The requirement pins the team OU, so cert renewal keeps grants. `just dr`
  prints it; `just verify-identity` refuses to build without the cert.
- **`just check` must be green before a commit.** Zero warnings, `--strict` lint.
- **Versions are written only by `just bump`** — a hook refuses hand-edits of
  `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
- **`appcast.xml` at the repo root is the live Sparkle feed** (raw URL on `main`).
  Deleting it, renaming `main`, or making the repo private strands every
  installed copy.
- **Deferred by decision, not oversight** — don't build unasked: caret-tracking
  indicator, LLM staging panel, log viewer, setup wizard, OpenAI/LAN providers,
  history audio playback, left/right modifier sides.

## Context boundaries

Before editing, read the local `CLAUDE.md`:

- `Utt/Clients/Api/CLAUDE.md` (+ `UttCore/Sources/UttCore/Api/CLAUDE.md`) — the
  listener, its reach, its token
- `Utt/Clients/Input/CLAUDE.md` — the event tap and the hotkey stream
- `Utt/Clients/Recording/CLAUDE.md` — capture, devices, the real-time boundary
- `Utt/Clients/System/CLAUDE.md` — permissions, sandbox, TCC timing
- `Utt/Clients/Transcription/CLAUDE.md` — model selection, live words
- `Utt/Clients/Extensions/CLAUDE.md` (+
  `UttCore/Sources/UttCore/Extensions/CLAUDE.md`) — capability negotiation, the
  log
- `Utt/App/CLAUDE.md` — activation, the `utt://` scheme
- `.claude/rules/isolation-boundaries.md` — applies across Recording, Input,
  Transcription

## Common change patterns

- **Add pure logic** → `UttCore/Sources/UttCore/`, with tests. Anything testable
  without a screen or a microphone belongs there.
- **Add a system capability** → a `@DependencyClient` struct in `Utt/Clients/`,
  `liveValue` forwarding to an actor (except the tap, which a C callback must
  call synchronously).
- **Add UI** → a `View` in `Utt/Views/<surface>/` reading `@Shared(.uttSettings)`
  directly, not bindings threaded through the store. A new surface opens with
  `PageHeader`; a new place to go is a case in `AppSection` (the whole rail).
- **Add a setting** → property + `CodingKey` + one `decodeIfPresent` line in
  `UttSettings` (every key decodes independently so an old file always loads),
  then a `SettingToggle` / `SettingRow` in a `SettingsGroup` on its page, bound
  via `$settings.binding(\.key)`. Explanation goes in `detail:`, not `.help`.
- **Add a Raycast command** → a `.tsx` in `raycast/src/` plus an entry in
  `raycast/package.json` `commands`. Reads go through files in Application
  Support (`raycast/src/utt.ts` is the only disk access); actions are `utt://`
  verbs. File contract: `raycast/README.md`.
- **Extension log / API endpoint / `utt://` verb / model** → see the Extensions,
  Api, App and Transcription `CLAUDE.md` respectively.
- **Redraw the app icon** → `just icon` (`tools/make-app-icon.py` writes
  `Utt/Resources/AppIcon.icon`; commit it, the build reads that). Keep it an Icon
  Composer `.icon`, not an appiconset: macOS 26 puts a legacy `.icns` on a light
  plate, which reads as a grey border.
- **Dark ground** → `Palette.lcdGround` plus `.environment(\.colorScheme, .dark)`;
  anything drawn with `.primary` inverts for free, no second palette.
- **Child → parent in TCA** → pattern-match the child action in `AppFeature`
  (`case .transcription(.pasteFinished(let pasted)):`). No delegate actions.
- **Release, version bump, appcast, notarization** → the `utt-release` skill
  (`.claude/skills/utt-release/SKILL.md`).

## Verification

`just check` = `just-fmt-check` + `loc-check` + `dir-check` + `lint` + `build` +
`test` + `raycast-check`.

- `just run` — build, kill the running copy, launch
- `just dr` — print the designated requirement (TCC stability check)
- `just test` — `swift test` in `UttCore`
- `just loc-check` / `dir-check` — thresholds in `.quality.json`
- `just raycast-check` — `tsc --noEmit` + `bun test` in `raycast/`; `just
  raycast-dev` loads the extension into Raycast with reload on save
- `just bench` — key release → extension hand-off through the real reducers and
  engines in a Release test host; writes `.build/bench/report.txt` with a Δ vs
  the last run. Safe beside the installed app (own `UTT_APPLICATION_SUPPORT`,
  private pasteboard, no ⌘V/tap/listener). `os_signpost` category `perf` marks
  the same stages for Instruments.

## Related context

- `agent.md` — verify loop, auto-fix commands, boundaries
- `docs/api.md` — the HTTP API: reach, auth, endpoints
- `docs/transcript-cleanup.md` — on-device cleanup stage: deletion-only contract,
  its setting, measured constants
- `docs/hotkey-semantics.md` — press/hold/double-tap spec behind the
  `HotKeyProcessor` tests
- `docs/phase0-results.md` — what the spike proved about taps, TCC and
  FluidAudio's API surface

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
