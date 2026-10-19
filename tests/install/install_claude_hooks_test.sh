#!/usr/bin/env bash
# scripts/install-claude-hooks.sh: idempotent upsert into Claude Code
# settings.json with timestamped, rotated backups. Runs against a fake HOME.
. "$(dirname "$0")/../testlib.sh"

export HOME="$TEST_TMP/home"
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"

install() { TIMESTAMP="${1:-20260730-120000}" bash "$ROOT_DIR/scripts/install-claude-hooks.sh" >/dev/null; }

json() { python3 -c "
import json, sys
data = json.load(open('$SETTINGS'))
$1
"; }

# Fresh install creates the file and registers every lifecycle event
install
[ -f "$SETTINGS" ] || fail "settings.json not created"
for event in SessionStart UserPromptSubmit Stop StopFailure Notification PermissionRequest PermissionDenied PostToolUse PostToolUseFailure PostCompact SessionEnd SubagentStart SubagentStop; do
  json "assert '$event' in data['hooks'], '$event missing'"
done
json "
hook = data['hooks']['Stop'][0]['hooks'][0]
assert hook['type'] == 'command', hook
assert hook['command'].endswith('hooks/claude.sh'), hook
assert hook['async'] is True, hook
assert data['hooks']['SessionStart'][0]['hooks'][0]['async'] is False, 'SessionStart must be sync'
"

# Idempotent: re-running never duplicates entries
install
assert_eq "13" "$(grep -c 'hooks/claude.sh' "$SETTINGS")" "one entry per event after re-run"

# Existing user hooks and unrelated settings are preserved
python3 - "$SETTINGS" <<'SEED'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["model"] = "opus"
data["hooks"]["Stop"][0]["hooks"].insert(0, {"type": "command", "command": "/usr/local/bin/my-bell.sh"})
json.dump(data, open(path, "w"), indent=2)
SEED
install
assert_file_contains "$SETTINGS" "my-bell.sh" "user hook preserved"
assert_file_contains "$SETTINGS" '"model": "opus"' "unrelated settings preserved"
assert_eq "13" "$(grep -c 'hooks/claude.sh' "$SETTINGS")" "still one entry per event"

# Backups: one per run, rotated to the 3 newest
install "20260730-130000"
install "20260730-140000"
install "20260730-150000"
backups=("$HOME/.claude/"settings.json.bak-agent-bar-*)
assert_eq "3" "${#backups[@]}" "three backups kept"
case "${backups[*]}" in
  *20260730-120000*) fail "oldest backup not pruned: ${backups[*]}" ;;
esac
