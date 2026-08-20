#!/usr/bin/env python3
"""Bump utt's version: project.yml, a release commit, an annotated tag.

The version lives in exactly one place — `MARKETING_VERSION` in project.yml —
and everything downstream reads it from there: the disk image's name, the
appcast, the tag a shipped file is traced back to. This script is that file's
only writer, so the three things that have to move together always do:

  MARKETING_VERSION       what a person sees, semver
  CURRENT_PROJECT_VERSION a monotonic integer; Sparkle orders updates by it, so
                          a reused build number is an update that never offers
  vX.Y.Z                  the annotated tag, `utt X.Y.Z`

Run it through `just bump`, which puts the quality gate in front of it.
"""

import re
import subprocess
import sys
from pathlib import Path

PROJECT = Path("project.yml")
PARTS = ("major", "minor", "patch")


def git(*args: str) -> str:
    return subprocess.run(
        ("git",) + args, capture_output=True, text=True, check=True
    ).stdout.strip()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def current() -> tuple[tuple[int, int, int], int]:
    text = PROJECT.read_text()
    version = re.search(r'MARKETING_VERSION: "(\d+)\.(\d+)\.(\d+)"', text)
    build = re.search(r'CURRENT_PROJECT_VERSION: "(\d+)"', text)
    if not version or not build:
        fail("project.yml has no MARKETING_VERSION / CURRENT_PROJECT_VERSION")
    return tuple(int(g) for g in version.groups()), int(build.group(1))


def last_tag() -> str | None:
    tags = git("tag", "--list", "v*", "--sort=-v:refname").splitlines()
    return tags[0] if tags else None


def derive(tag: str | None) -> tuple[str, str]:
    """Conventional commits decide the part: `feat` is a minor, `!` or a
    BREAKING CHANGE trailer is a major, everything else is a patch."""
    span = f"{tag}..HEAD" if tag else "HEAD"
    commits = [c for c in git("log", span, "--format=%s%x1f%b%x1e").split("\x1e") if c.strip()]
    if not commits:
        fail(f"no commits since {tag or 'the start'} — nothing to release")
    subjects = [c.split("\x1f")[0].strip() for c in commits]
    breaking = any(re.match(r"^\w+(\([^)]*\))?!:", s) for s in subjects) or "BREAKING CHANGE" in "\n".join(commits)
    feature = any(re.match(r"^feat(\([^)]*\))?:", s) for s in subjects)
    if breaking:
        return "major", f"{len(commits)} commit(s) since {tag}, one of them breaking"
    if feature:
        return "minor", f"{len(commits)} commit(s) since {tag}, including a feat"
    return "patch", f"{len(commits)} commit(s) since {tag}, all fixes and chores"


def bumped(version: tuple[int, int, int], part: str) -> tuple[int, int, int]:
    major, minor, patch = version
    if part == "major":
        return (major + 1, 0, 0)
    if part == "minor":
        return (major, minor + 1, 0)
    return (major, minor, patch + 1)


def main() -> None:
    args = [a for a in sys.argv[1:] if a]
    dry = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    if len(args) > 1 or (args and args[0] not in PARTS):
        fail(f"usage: bump-version.py [{'|'.join(PARTS)}] [--dry-run]")

    version, build = current()
    tag = last_tag()
    if args:
        part, why = args[0], "asked for"
    else:
        part, why = derive(tag)
        # Semver's own rule for 0.x: nothing is stable yet, so a breaking change
        # is a minor. Reaching 1.0.0 is a decision, never a side effect of a
        # commit message — pass `major` by hand for that.
        if part == "major" and version[0] == 0:
            part, why = "minor", why + " — pre-1.0, so a minor"

    nxt = bumped(version, part)
    text = ".".join(str(n) for n in nxt)
    print(f"{'.'.join(str(n) for n in version)} → {text}  ({part}: {why})")
    print(f"build {build} → {build + 1}")
    notes = Path(f"docs/RELEASE-{text}.md")
    if not notes.exists():
        print(f"note: {notes} does not exist yet — write it before publishing")
    if dry:
        return

    if git("status", "--porcelain"):
        fail("working tree is dirty — a release commit may only touch project.yml")
    if f"v{text}" in git("tag", "--list", f"v{text}"):
        fail(f"tag v{text} already exists")

    source = PROJECT.read_text()
    source = source.replace(
        f'MARKETING_VERSION: "{".".join(str(n) for n in version)}"',
        f'MARKETING_VERSION: "{text}"',
    ).replace(
        f'CURRENT_PROJECT_VERSION: "{build}"', f'CURRENT_PROJECT_VERSION: "{build + 1}"'
    )
    PROJECT.write_text(source)

    git("add", str(PROJECT))
    git("commit", "-m", f"release: {text}")
    git("tag", "-a", f"v{text}", "-m", f"utt {text}")
    print(f"→ committed and tagged v{text}. Push with: git push --follow-tags")


if __name__ == "__main__":
    main()
