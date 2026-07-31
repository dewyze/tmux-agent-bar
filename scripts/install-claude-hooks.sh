#!/usr/bin/env bash
# Register hooks/claude.sh for every lifecycle event in Claude Code's
# settings.json. Idempotent; backs up the file first (3 backups kept).
# Never auto-run — invoke explicitly.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
HOOK_COMMAND="$ROOT_DIR/hooks/claude.sh"

mkdir -p "$(dirname "$SETTINGS")"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-agent-bar-$TIMESTAMP"
  ls -1t "$SETTINGS".bak-agent-bar-* 2>/dev/null | tail -n +4 | while IFS= read -r old; do
    rm -f "$old"
  done
else
  printf '{}\n' > "$SETTINGS"
fi

SETTINGS="$SETTINGS" HOOK_COMMAND="$HOOK_COMMAND" python3 <<'PY'
import json
import os

settings_path = os.environ["SETTINGS"]
hook_command = os.environ["HOOK_COMMAND"]

# SessionStart stays synchronous so the pane is marked before the first
# prompt; everything else must never block Claude.
EVENTS = {
    "SessionStart": False,
    "UserPromptSubmit": True,
    "Stop": True,
    "StopFailure": True,
    "Notification": True,
    "PermissionRequest": True,
    "SessionEnd": True,
    "SubagentStart": True,
    "SubagentStop": True,
}

with open(settings_path) as f:
    data = json.load(f)

hooks = data.setdefault("hooks", {})
for event, run_async in EVENTS.items():
    rules = hooks.setdefault(event, [])
    rule = next((r for r in rules if not r.get("matcher")), None)
    if rule is None:
        rule = {"matcher": "", "hooks": []}
        rules.append(rule)
    entries = rule.setdefault("hooks", [])
    entry = next((e for e in entries if e.get("command") == hook_command), None)
    if entry is None:
        entry = {"type": "command", "command": hook_command}
        entries.append(entry)
    entry["timeout"] = 10
    entry["async"] = run_async

with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

printf 'Registered %s in %s\n' "$HOOK_COMMAND" "$SETTINGS"
