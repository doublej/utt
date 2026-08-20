#!/usr/bin/env python3
"""Cases the version guard must block, and cases it must leave alone."""
import json
import subprocess

GUARD = ".claude/scripts/guard_version_edit.py"
KEY = "MARKETING" + "_VERSION"
YML = "project" + ".yml"

CASES = [
    (2, "Edit the version in project.yml",
     {"tool_name": "Edit", "tool_input": {"file_path": f"/x/{YML}", "new_string": f'{KEY}: "0.4.0"'}}),
    (2, "sed -i the version",
     {"tool_name": "Bash", "tool_input": {"command": f'sed -i "" s/{KEY}/x/ {YML}'}}),
    (2, "redirect a new project.yml",
     {"tool_name": "Bash", "tool_input": {"command": f'echo \'{KEY}: "9.0.0"\' > {YML}'}}),
    (2, "python write_text on project.yml",
     {"tool_name": "Bash", "tool_input": {"command": f'p = Path("{YML}"); p.write_text(s.replace("{KEY}", "x"))'}}),
    (0, "Edit an unrelated key in project.yml",
     {"tool_name": "Edit", "tool_input": {"file_path": f"/x/{YML}", "new_string": "deploymentTarget: 26.0"}}),
    (0, "grep the version",
     {"tool_name": "Bash", "tool_input": {"command": f"grep {KEY} {YML}"}}),
    (0, "the sanctioned bump",
     {"tool_name": "Bash", "tool_input": {"command": "python3 tools/bump-version.py minor"}}),
    (0, "write docs that mention the version",
     {"tool_name": "Write", "tool_input": {"file_path": "/x/CLAUDE.md", "content": f"{KEY} lives in {YML}"}}),
    (0, "read project.yml",
     {"tool_name": "Read", "tool_input": {"file_path": YML}}),
]

failed = 0
for expected, label, payload in CASES:
    got = subprocess.run(["python3", GUARD], input=json.dumps(payload),
                         capture_output=True, text=True).returncode
    ok = got == expected
    failed += not ok
    print(f"{'ok  ' if ok else 'FAIL'}  expected {expected}, got {got}  {label}")

print("\nall clear" if not failed else f"\n{failed} case(s) wrong")
raise SystemExit(1 if failed else 0)
