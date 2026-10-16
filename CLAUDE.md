# utt

> Native macOS on-device transcription — hold a hotkey, speak, release, text at the cursor

## What this is

All-native, on-device: a TCA app (`Utt/`) plus `UttCore/`, a pure-logic SPM
package holding all the tests. Parakeet TDT v3 via FluidAudio by default,
WhisperKit alongside. `project.yml` is the XcodeGen source; `Utt.xcodeproj` is
generated — never edit it. Layout and runtime path: `docs/architecture.md`.

## Invariants

Folder invariants live in the nested `CLAUDE.md` files (Api, Input, Recording,
System, Transcription, Extensions, App) and `.claude/rules/`. Global:

- **The signing identity is fixed.** `CODE_SIGN_IDENTITY` in `project.yml` is the
  Developer ID cert's SHA-1, Debug and Release. TCC keys grants to the designated
  requirement, so another cert (or ad-hoc `-`, new every build) silently resets
  Accessibility, Input Monitoring and Microphone. It pins the team OU, so cert
  renewal keeps grants. `just dr` prints it;
  `just verify-identity` refuses to build without the cert.
- **`just check` must be green before a commit.** Zero warnings, `--strict` lint.
- **Versions are written only by `just bump`** (hook-guarded).
- **`appcast.xml` on `main` is the live Sparkle feed.** Deleting it, renaming
  `main`, or making the repo private strands every installed copy.
- **Deferred by decision** — don't build unasked: caret-tracking indicator, LLM
  staging panel, log viewer, setup wizard, OpenAI/LAN providers, history audio
  playback, left/right modifier sides.

## Common change patterns

- **Pure logic** → `UttCore/Sources/UttCore/`, with tests — anything testable
  without a screen or a microphone.
- **System capability** → `@DependencyClient` in `Utt/Clients/`, `liveValue`
  forwarding to an actor (except the tap: a C callback calls it synchronously).
- **UI** → a `View` in `Utt/Views/<surface>/` reading `@Shared(.uttSettings)`
  directly. New surface opens with `PageHeader`; new destination = a case in
  `AppSection` (the whole rail).
- **Setting** → property + `CodingKey` + one `decodeIfPresent` in `UttSettings`
  (keys decode independently so old files load), then a `SettingToggle` /
  `SettingRow` in a `SettingsGroup`, bound via `$settings.binding(\.key)`.
  Explanation in `detail:`, not `.help`.
- **Raycast command** → `.tsx` in `raycast/src/` + `raycast/package.json`
  `commands`. Reads are Application Support files (only `raycast/src/utt.ts`
  touches disk); actions are `utt://` verbs. Contract: `raycast/README.md`.
- **App icon** → `just icon`, commit `Utt/Resources/AppIcon.icon`. Keep it an
  Icon Composer `.icon`: macOS 26 gives a legacy `.icns` a grey border.
- **Dark ground** → `Palette.lcdGround` + `.environment(\.colorScheme, .dark)`.
- **Child → parent in TCA** → pattern-match the child action in `AppFeature`;
  no delegate actions.
- **Release / bump / appcast / notarize** → `utt-release` skill.

## Verification

`just check` = `just-fmt-check` + `loc-check` + `dir-check` + `lint` + `build` +
`test` + `raycast-check`. Also: `just run` (build, relaunch), `just dr`,
`just test` (`UttCore`), `just raycast-dev`. `just bench` times key release →
extension hand-off in a Release test host (`.build/bench/report.txt`); safe beside
the installed app — own `UTT_APPLICATION_SUPPORT`, no ⌘V, tap or listener.

## Related context

`agent.md` (verify loop), `docs/api.md`, `docs/transcript-cleanup.md`,
`docs/hotkey-semantics.md`, `docs/phase0-results.md`, `.quality.json`.

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
