#!/usr/bin/env bash
# Claude Code plugin packaging: .claude-plugin/plugin.json + marketplace.json
# + hooks/hooks.json. The hooks.json event set must match the legacy
# settings.json installer exactly — two install paths, one contract.
. "$(dirname "$0")/../testlib.sh"

json_ok() { python3 -c "import json; json.load(open('$1'))" 2>/dev/null || fail "invalid JSON: $1"; }

json_ok "$ROOT_DIR/.claude-plugin/plugin.json"
json_ok "$ROOT_DIR/.claude-plugin/marketplace.json"
json_ok "$ROOT_DIR/hooks/hooks.json"

python3 - "$ROOT_DIR" <<'PY'
import json
import subprocess
import sys

root = sys.argv[1]

plugin = json.load(open(f"{root}/.claude-plugin/plugin.json"))
assert plugin.get("name") == "tmux-agent-bar", plugin
assert plugin.get("version"), "plugin.json needs a version"

market = json.load(open(f"{root}/.claude-plugin/marketplace.json"))
names = [p.get("name") for p in market.get("plugins", [])]
assert "tmux-agent-bar" in names, market

hooks = json.load(open(f"{root}/hooks/hooks.json"))["hooks"]
for event, rules in hooks.items():
    for rule in rules:
        for entry in rule["hooks"]:
            assert entry["type"] == "command", (event, entry)
            assert entry["command"].startswith('"${CLAUDE_PLUGIN_ROOT}"/hooks/claude.sh'), (event, entry)
            assert entry.get("timeout"), (event, entry)

# Drift guard: plugin hooks and settings installer register the same events
installer = open(f"{root}/scripts/install-claude-hooks.sh").read()
start = installer.index("EVENTS = {")
end = installer.index("}", start)
installer_events = {
    line.split('"')[1]
    for line in installer[start:end].splitlines()
    if line.strip().startswith('"')
}
assert set(hooks) == installer_events, (
    f"plugin/installer drift: only-plugin={set(hooks) - installer_events} "
    f"only-installer={installer_events - set(hooks)}"
)

# SessionStart stays synchronous in both paths
session_start = hooks["SessionStart"][0]["hooks"][0]
assert session_start.get("async") is False, session_start
assert hooks["Stop"][0]["hooks"][0].get("async") is True, "async events stay async"
PY
