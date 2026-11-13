#!/usr/bin/env bash
# Register hooks/codex.sh for every lifecycle event in Codex's hooks.json.
# Idempotent; backs up the file first (3 backups kept). Never auto-run —
# invoke explicitly. Codex skips new hooks until they are approved: run
# /hooks inside Codex afterwards. Badges also need Codex to run without its
# shared background server (see hooks/codex.sh).
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

# Every event lib/parse-codex.py maps (a test keeps the two in step), and
# whether Codex may run the hook without waiting for it. SessionStart fires
# together with the first prompt: it stays synchronous so its idle cannot
# land after the prompt's running.
EVENTS = {
    "SessionStart": False,
    "SessionEnd": True,
    "UserPromptSubmit": True,
    "PostToolUse": True,
    "PermissionRequest": True,
    "Interrupt": True,
    "PostCompact": True,
    "SubagentStart": True,
    "SubagentStop": True,
    "Stop": True,
}

with open(hooks_path) as f:
    data = json.load(f)

hooks = data.setdefault("hooks", {})
for event, run_async in EVENTS.items():
    rules = hooks.setdefault(event, [])
    entry = next(
        (
            entry
            for rule in rules
            for entry in rule.get("hooks", [])
            if entry.get("command") == hook_command
        ),
        None,
    )
    if entry is None:
        entry = {"type": "command", "command": hook_command}
        rules.append({"hooks": [entry]})
    # Codex lists a hook under its statusMessage, and without a timeout
    # waits up to 600s for it.
    entry["statusMessage"] = "tmux-agent-bar"
    entry["timeout"] = 10
    entry["async"] = run_async

with open(hooks_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

printf 'Registered %s in %s\n' "$HOOK_COMMAND" "$HOOKS"
printf 'Codex skips new hooks until you approve them: run /hooks inside Codex.\n'
cat <<'NOTE'
Badges need Codex to run without its shared background server, which hides
the pane from hooks (openai/codex#48500). Either add to ~/.codex/config.toml:
  [features]
  daemon_auto_start = false
or start Codex with: codex --no-daemon
NOTE
