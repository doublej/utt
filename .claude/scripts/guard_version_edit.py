#!/usr/bin/env python3
"""Refuse hand-edits of the version.

`tools/bump-version.py` moves MARKETING_VERSION, CURRENT_PROJECT_VERSION and the
vX.Y.Z tag in one commit. Moving one of them on its own is how a build ships that
no tag points at, or a Sparkle build number that stops increasing — an update
nobody is ever offered, on machines that cannot be reached any other way.

ponytail: a guardrail, not a sandbox. It reads the obvious write paths — the edit
tools, a redirect or `sed -i` aimed at project.yml, a Path().write_text — and a
determined detour around it is not worth the false positives that closing it
would cost. Every mention of the version in prose or in a script has to stay
writable.
"""

import json
import re
import sys

KEYS = ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION")
# A redirect, tee or in-place sed reaching project.yml *on the same line* — so a
# heredoc that merely talks about the file downstream is left alone.
REDIRECT = re.compile(r"(>>?|tee|sed\s+-i\S*|perl\s+-i\S*)[^\n|;&]*project\.yml")
# `Path("project.yml")`, not a bare mention: a doc that talks about the file and
# a script that opens it read the same to a substring search.
HANDLE = re.compile(r"""Path\(\s*["']project\.yml["']""")
MESSAGE = (
    "Blocked: the version is not edited by hand. Run `just bump "
    "[major|minor|patch]` (preview with `just next`) — it moves project.yml, the "
    "build number and the tag together, behind `just check`."
)

payload = json.load(sys.stdin)
tool = payload.get("tool_name", "")
data = payload.get("tool_input", {})

if tool == "Bash":
    command = data.get("command", "")
    writes = bool(REDIRECT.search(command)) or (
        bool(HANDLE.search(command)) and "write_text" in command
    )
    text = command if writes else ""
elif tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    text = json.dumps(data) if "project.yml" in data.get("file_path", "") else ""
else:
    text = ""

if any(key in text for key in KEYS):
    print(MESSAGE, file=sys.stderr)
    sys.exit(2)
