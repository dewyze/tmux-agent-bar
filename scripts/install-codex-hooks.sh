#!/usr/bin/env bash
# Register hooks/codex.sh for every lifecycle event in Codex's hooks.json.
# Idempotent; backs up the file first (3 backups kept). Never auto-run —
# invoke explicitly. Codex skips new hooks until they are approved: run
# /hooks inside Codex afterwards.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

HOOKS="${CODEX_HOOKS:-$HOME/.codex/hooks.json}"
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
HOOK_COMMAND="$ROOT_DIR/hooks/codex.sh"

mkdir -p "$(dirname "$HOOKS")"

if [ -f "$HOOKS" ]; then
  cp "$HOOKS" "$HOOKS.bak-agent-bar-$TIMESTAMP"
  ls -1t "$HOOKS".bak-agent-bar-* 2>/dev/null | tail -n +4 | while IFS= read -r old; do
    rm -f "$old"
  done
else
  printf '{}\n' > "$HOOKS"
fi

HOOKS="$HOOKS" HOOK_COMMAND="$HOOK_COMMAND" python3 <<'PY'
import json
import os

hooks_path = os.environ["HOOKS"]
hook_command = os.environ["HOOK_COMMAND"]

# Every event lib/parse-codex.py maps (a test keeps the two in step).
EVENTS = [
    "SessionStart",
    "SessionEnd",
    "UserPromptSubmit",
    "PostToolUse",
    "PermissionRequest",
    "Interrupt",
    "PostCompact",
    "SubagentStart",
    "SubagentStop",
    "Stop",
]

with open(hooks_path) as f:
    data = json.load(f)

hooks = data.setdefault("hooks", {})
for event in EVENTS:
    rules = hooks.setdefault(event, [])
    registered = any(
        entry.get("command") == hook_command
        for rule in rules
        for entry in rule.get("hooks", [])
    )
    if not registered:
        rules.append({"hooks": [{"type": "command", "command": hook_command}]})

with open(hooks_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

printf 'Registered %s in %s\n' "$HOOK_COMMAND" "$HOOKS"
printf 'Codex skips new hooks until you approve them: run /hooks inside Codex.\n'
