---
name: utt-release
description: Cut and publish a utt release — version bump, archive, notarize, dmg, GitHub release, Sparkle appcast. Use when asked to release, publish, bump the version, or touch appcast.xml, Sparkle keys or notarization.
---

# Releasing utt

## Versioning

Semver; `just bump` is the only writer. It moves all three together, behind
`just check`, in one `release: X.Y.Z` commit:

- `MARKETING_VERSION` — what a person sees; names the dmg and the zip
- `CURRENT_PROJECT_VERSION` — monotonic integer. Sparkle orders updates by it, so
  a reused build number is an update nobody is ever offered
- annotated tag `vX.Y.Z`, message `utt X.Y.Z`

A hook refuses hand-edits of either key (`.claude/scripts/guard_version_edit.py`,
with its own test).

- `just next` — what the bump would decide, without deciding it
- `just bump` — read the part off the conventional commits since the last tag
- `just bump major|minor|patch` — overrule it

Part from commits: **patch** `fix:` / `perf:` / `refactor:` (nothing visible
changes); **minor** `feat:` (new setting, `utt://` verb, engine or model);
**major** `feat!:` or `BREAKING CHANGE:` (removed verb, settings key no longer
read, default that cannot be migrated). While on `0.x` a derived major lands as a
minor; reaching 1.0.0 takes an explicit `just bump major`.

## Pipeline

1. `just bump` — first, since every artifact is named from `MARKETING_VERSION`.
2. Write `docs/RELEASE-X.Y.Z.md` by hand (`bump` only warns when it is missing).
3. `just publish` — `archive` → `export-app` → `notarize` → `dmg`, pushes the
   tag, creates the GitHub release from `docs/RELEASE-X.Y.Z.md` with dmg + zip,
   then rewrites and commits `appcast.xml`.

- `just dmg` is the shippable artifact: drag-to-Applications image, itself signed
  and notarized, because Gatekeeper checks the container first. It has no custom
  window background or icon layout (would need Finder AppleScript).
- `export-app` writes `release/ExportOptions.plist` itself.
- `notarize` needs the `utt-notary` keychain profile (`xcrun notarytool
  store-credentials` + app-specific password), or run
  `onenv export utt -- just publish` to take the same credentials from
  1Password. Use the onenv form wherever no keychain dialog can appear (agent
  shell, Mac in dark wake).
- `just sparkle-keys` once, and **back the private key up** — losing it means
  installed copies can never be updated again.

## Appcast invariants

- **`appcast.xml` at the repo root is the live feed.** `SUFeedURL` is its
  `raw.githubusercontent.com` URL on `main`. Deleting it, renaming the branch, or
  making the repo private strands every installed copy.
- **`release/appcast/` is not disposable.** `generate_appcast` carries previous
  entries forward only from the appcast next to the archives; generating into the
  wiped `release/export/` publishes a feed with only the newest version.
- **The appcast is committed last** — it must never name a download not yet
  attached to the release.
- **Deltas are off** (`--maximum-deltas 0`, `justfile` `publish`): a delta is an
  extra upload, and an advertised delta that 404s fails the update.
