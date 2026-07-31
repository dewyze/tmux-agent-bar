#!/usr/bin/env bash
# hooks/claude.sh: payload in, batched `tmux set -p` out. tmux is stubbed;
# the stub logs argv and answers @agent_subagents reads from a fixture file.
. "$(dirname "$0")/../testlib.sh"

STUB_LOG="$TEST_TMP/tmux.log"
COUNT_FILE="$TEST_TMP/subagent_count"
mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STUB_LOG"
if [ "\$1" = "show-options" ]; then
  cat "$COUNT_FILE" 2>/dev/null
fi
STUB
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"
export TMUX_PANE="%7"

run_hook() {
  rm -f "$STUB_LOG"
  printf '%s' "$1" | bash "$ROOT_DIR/hooks/claude.sh"
}

log() { cat "$STUB_LOG" 2>/dev/null || true; }

# Plain lifecycle event writes app, state, updated timestamp in one invocation
run_hook '{"hook_event_name":"UserPromptSubmit"}'
assert_contains "$(log)" "set-option -p -t %7 @agent_app claude ; set-option -p -t %7 @agent_state running" "batched write"
assert_contains "$(log)" "@agent_updated " "timestamp written"
assert_eq "1" "$(grep -c 'set-option' "$STUB_LOG")" "single tmux invocation for writes"

# needs-input
run_hook '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
assert_contains "$(log)" "@agent_state needs-input" "needs-input state"

# Unknown events must not touch tmux at all
run_hook '{"hook_event_name":"PreToolUse"}'
assert_eq "" "$(log)" "no-op for unknown event"

# No pane id -> no writes
rm -f "$STUB_LOG"
printf '%s' '{"hook_event_name":"Stop"}' | TMUX_PANE="" bash "$ROOT_DIR/hooks/claude.sh"
assert_eq "" "$(log)" "no-op without TMUX_PANE"

# Subagent refcount: start increments and forces subagent-running
printf '1' > "$COUNT_FILE"
run_hook '{"hook_event_name":"SubagentStart"}'
assert_contains "$(log)" "@agent_state subagent-running" "start state"
assert_contains "$(log)" "@agent_subagents 2" "start increments"

# stop decrements; still subagent-running while count > 0
printf '2' > "$COUNT_FILE"
run_hook '{"hook_event_name":"SubagentStop"}'
assert_contains "$(log)" "@agent_state subagent-running" "stop with remaining subagents"
assert_contains "$(log)" "@agent_subagents 1" "stop decrements"

# last stop returns to running; count clamps at 0
printf '1' > "$COUNT_FILE"
run_hook '{"hook_event_name":"SubagentStop"}'
assert_contains "$(log)" "@agent_state running" "last stop back to running"
assert_contains "$(log)" "@agent_subagents 0" "count reaches 0"

# Reset guard: a non-subagent terminal event zeroes a stuck refcount
printf '3' > "$COUNT_FILE"
run_hook '{"hook_event_name":"Stop"}'
assert_contains "$(log)" "@agent_state done" "done state"
assert_contains "$(log)" "@agent_subagents 0" "reset guard zeroes count"

# needs-input leaves the refcount alone
printf '2' > "$COUNT_FILE"
run_hook '{"hook_event_name":"PermissionRequest"}'
assert_contains "$(log)" "@agent_subagents 2" "needs-input preserves count"

# Garbage count from tmux is treated as 0
printf 'junk' > "$COUNT_FILE"
run_hook '{"hook_event_name":"SubagentStart"}'
assert_contains "$(log)" "@agent_subagents 1" "non-numeric count resets"
