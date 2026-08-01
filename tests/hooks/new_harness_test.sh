#!/usr/bin/env bash
# The "adding a harness" recipe, executed: a new agent integration is exactly
# (1) a pure parser lib/parse-<app>.py speaking the 3-line protocol and
# (2) a 3-line hooks/<app>.sh delegating to run_agent_hook. This test builds
# a fake harness from that recipe and proves it gets full writer behavior —
# schema stamping, state machine, exit-unsets — for free.
. "$(dirname "$0")/../testlib.sh"

STUB_LOG="$TEST_TMP/tmux.log"
mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STUB_LOG"
STUB
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"
export TMUX_PANE="%3"

# A harness author writes these two files and nothing else.
# Recipe file 1: the parser (pure, 3-line protocol)
FAKE_ROOT="$TEST_TMP/plugin"
mkdir -p "$FAKE_ROOT/hooks" "$FAKE_ROOT/lib"
cp "$ROOT_DIR/lib/hook-lib.sh" "$FAKE_ROOT/lib/"
cp "$ROOT_DIR/lib/parse-claude.py" "$FAKE_ROOT/lib/"  # coexisting harness
cp "$ROOT_DIR/hooks/claude.sh" "$FAKE_ROOT/hooks/"
printf '0.0-test\n' > "$FAKE_ROOT/VERSION"
cat > "$FAKE_ROOT/lib/parse-fakebot.py" <<'PY'
import json, os

data = json.loads(os.environ.get("HOOK_PAYLOAD", "{}") or "{}")
kind = data.get("event", "")
states = {"go": "running", "ask": "needs-input", "fin": "done", "bye": "exit"}
state = states.get(kind, "")
if state:
    print(state)
    print("")
    print(data.get("log", ""))
PY

# Recipe file 2: the wrapper
cat > "$FAKE_ROOT/hooks/fakebot.sh" <<'SH'
#!/usr/bin/env bash
. "$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)/lib/hook-lib.sh"
run_agent_hook fakebot "$@"
SH
chmod +x "$FAKE_ROOT/hooks/fakebot.sh"

run_fake() {
  rm -f "$STUB_LOG"
  printf '%s' "$1" | bash "$FAKE_ROOT/hooks/fakebot.sh"
}
log() { cat "$STUB_LOG" 2>/dev/null || true; }

# Full writer behavior, no fakebot-specific writer code anywhere:
run_fake '{"event":"go"}'
assert_contains "$(log)" "@agent_app fakebot" "app identity"
assert_contains "$(log)" "@agent_state running" "state written"
assert_contains "$(log)" "@agent_schema 1" "schema stamped"
assert_contains "$(log)" "@agent_updated " "timestamp written"

run_fake '{"event":"ask","log":"/tmp/fake.jsonl"}'
assert_contains "$(log)" "@agent_state needs-input" "needs-input"
assert_contains "$(log)" "@agent_transcript /tmp/fake.jsonl" "transcript recorded"

run_fake '{"event":"nonsense"}'
assert_not_contains "$(log)" "set-option" "unknown events are no-ops"

run_fake '{"event":"bye"}'
assert_contains "$(log)" "set-option -pu -t %3 @agent_state" "exit unsets"

# The claude wrapper still works from the same shared lib (no regression)
printf '%s' '{"hook_event_name":"Stop"}' | TMUX_PANE="%3" bash "$FAKE_ROOT/hooks/claude.sh"
assert_contains "$(log)" "@agent_app claude" "claude wrapper unaffected"
