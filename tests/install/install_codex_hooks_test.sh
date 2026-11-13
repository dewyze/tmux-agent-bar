#!/usr/bin/env bash
# scripts/install-codex-hooks.sh: idempotent upsert into Codex's hooks.json
# with timestamped, rotated backups. Runs against a fake HOME.
. "$(dirname "$0")/../testlib.sh"

export HOME="$TEST_TMP/home"
HOOKS="$HOME/.codex/hooks.json"

install() { TIMESTAMP="${1:-20261112-120000}" bash "$ROOT_DIR/scripts/install-codex-hooks.sh" >/dev/null; }

json() { python3 -c "
import json, sys
data = json.load(open('$HOOKS'))
$1
"; }

# Fresh install creates the file and registers every event the parser maps
install
[ -f "$HOOKS" ] || fail "hooks.json not created"
mapped="$(grep -oE 'event == "[A-Za-z]+"' "$ROOT_DIR/lib/parse-codex.py" | grep -oE '"[A-Za-z]+"' | tr -d '"' | sort -u)"
[ -n "$mapped" ] || fail "no events found in the parser"
for event in $mapped; do
  json "assert '$event' in data['hooks'], '$event mapped by the parser but not registered'"
done
json "
hook = data['hooks']['Stop'][0]['hooks'][0]
assert hook['type'] == 'command', hook
assert hook['command'].endswith('hooks/codex.sh'), hook
# Codex lists a hook under its statusMessage ("Unnamed hook" without one),
# waits for sync hooks, and gives them 600s by default.
assert hook['statusMessage'] == 'tmux-agent-bar', hook
assert hook['async'] is True, hook
assert hook['timeout'] == 10, hook
# SessionStart fires together with the first prompt: it stays synchronous
# so its idle cannot land after the prompt's running.
assert data['hooks']['SessionStart'][0]['hooks'][0]['async'] is False, 'SessionStart must be sync'
"

# An entry from an earlier install gains the fields in place
python3 - "$HOOKS" <<'OLD'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
entry = data["hooks"]["Stop"][0]["hooks"][0]
for key in ("statusMessage", "async", "timeout"):
    del entry[key]
json.dump(data, open(path, "w"), indent=2)
OLD
install
json "
hook = data['hooks']['Stop'][0]['hooks'][0]
assert hook['statusMessage'] == 'tmux-agent-bar' and hook['async'] is True and hook['timeout'] == 10, hook
assert len(data['hooks']['Stop']) == 1, data['hooks']['Stop']
"
count="$(echo "$mapped" | wc -l | tr -d ' ')"

# Idempotent: re-running never duplicates entries
install
assert_eq "$count" "$(grep -c 'hooks/codex.sh' "$HOOKS")" "one entry per event after re-run"

# Existing user hooks and unrelated keys are preserved
python3 - "$HOOKS" <<'SEED'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["other"] = "kept"
data["hooks"]["Stop"].insert(0, {"matcher": "", "hooks": [{"type": "command", "command": "/usr/local/bin/my-bell.sh"}]})
data["hooks"]["PreToolUse"] = [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/usr/local/bin/policy.sh"}]}]
json.dump(data, open(path, "w"), indent=2)
SEED
install
assert_file_contains "$HOOKS" "my-bell.sh" "user hook preserved"
assert_file_contains "$HOOKS" "policy.sh" "user hook on an unmapped event preserved"
assert_file_contains "$HOOKS" '"other": "kept"' "unrelated keys preserved"
assert_eq "$count" "$(grep -c 'hooks/codex.sh' "$HOOKS")" "still one entry per event"

# Backups: one per run, rotated to the 3 newest
install "20261112-130000"
install "20261112-140000"
install "20261112-150000"
backups=("$HOME/.codex/"hooks.json.bak-agent-bar-*)
assert_eq "3" "${#backups[@]}" "three backups kept"
case "${backups[*]}" in
  *20261112-120000*) fail "oldest backup not pruned: ${backups[*]}" ;;
esac

# The installer says what Codex needs before badges appear: approval, and
# no shared background server.
output="$(TIMESTAMP=20261112-120009 bash "$ROOT_DIR/scripts/install-codex-hooks.sh")"
assert_contains "$output" "/hooks" "approval reminder"
assert_contains "$output" "daemon_auto_start = false" "background server reminder"
assert_contains "$output" "--no-daemon" "per-launch alternative"
