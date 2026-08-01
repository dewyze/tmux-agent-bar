#!/usr/bin/env bash
# hooks/claude.sh: payload in, batched `tmux set -p` out. tmux is stubbed;
# the stub logs argv and answers @agent_subagents reads from a fixture file.
. "$(dirname "$0")/../testlib.sh"

STUB_LOG="$TEST_TMP/tmux.log"
COUNT_FILE="$TEST_TMP/subagent_count"
TRACE_OPT_FILE="$TEST_TMP/trace_option"
mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STUB_LOG"
if [ "\$1" = "show-options" ]; then
  case "\$*" in
    *@agent_bar_trace*) cat "$TRACE_OPT_FILE" 2>/dev/null ;;
    *) cat "$COUNT_FILE" 2>/dev/null ;;
  esac
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

# The writer stamps its version so plugin-copy/checkout skew is observable
run_hook '{"hook_event_name":"UserPromptSubmit"}'
assert_contains "$(log)" "@agent_writer_version $(cat "$ROOT_DIR/VERSION")" "writer version stamped"

# transcript_path in the payload is recorded for needs-input verification
run_hook '{"hook_event_name":"UserPromptSubmit","transcript_path":"/tmp/t.jsonl"}'
assert_contains "$(log)" "@agent_transcript /tmp/t.jsonl" "transcript recorded"
run_hook '{"hook_event_name":"UserPromptSubmit"}'
assert_not_contains "$(log)" "@agent_transcript" "no transcript -> option untouched"

# needs-input
run_hook '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
assert_contains "$(log)" "@agent_state needs-input" "needs-input state"

# Unknown events must never write options (the read-only trace lookup is fine)
run_hook '{"hook_event_name":"PreToolUse"}'
assert_not_contains "$(log)" "set-option" "no writes for unknown event"

# No pane id -> no writes
rm -f "$STUB_LOG"
printf '%s' '{"hook_event_name":"Stop"}' | TMUX_PANE="" bash "$ROOT_DIR/hooks/claude.sh"
assert_not_contains "$(log)" "set-option" "no writes without TMUX_PANE"

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

# A stale SubagentStop (count already 0, e.g. a background agent finishing
# after Stop) must not write anything — it would resurrect a done badge
printf '0' > "$COUNT_FILE"
run_hook '{"hook_event_name":"SubagentStop"}'
assert_not_contains "$(log)" "set-option" "stale SubagentStop is a no-op"

# PostToolUse is soft running: no refcount reset, subagent-running preserved
printf '2' > "$COUNT_FILE"
run_hook '{"hook_event_name":"PostToolUse"}'
assert_contains "$(log)" "@agent_state subagent-running" "soft running respects subagents"
assert_contains "$(log)" "@agent_subagents 2" "soft running preserves count"
printf '0' > "$COUNT_FILE"
run_hook '{"hook_event_name":"PostToolUse"}'
assert_contains "$(log)" "@agent_state running" "soft running plain when no subagents"

# Garbage count from tmux is treated as 0
printf 'junk' > "$COUNT_FILE"
run_hook '{"hook_event_name":"SubagentStart"}'
assert_contains "$(log)" "@agent_subagents 1" "non-numeric count resets"

# SessionEnd removes the agent from the bar: all options unset, none written
run_hook '{"hook_event_name":"SessionEnd"}'
assert_contains "$(log)" "set-option -pu -t %7 @agent_state" "exit unsets state"
assert_contains "$(log)" "set-option -pu -t %7 @agent_app" "exit unsets app"
assert_contains "$(log)" "set-option -pu -t %7 @agent_transcript" "exit unsets transcript"
assert_not_contains "$(log)" "@agent_state exit" "exit is not written as a state"

# Tracing: @agent_bar_trace names a log file; every event appends one line
# with the payload and the parse result, including no-op events.
TRACE_FILE="$TEST_TMP/trace.log"
printf '%s' "$TRACE_FILE" > "$TRACE_OPT_FILE"
run_hook '{"hook_event_name":"Stop"}'
assert_file_contains "$TRACE_FILE" "Stop" "trace records event"
assert_file_contains "$TRACE_FILE" "state=done" "trace records parsed state"
assert_file_contains "$TRACE_FILE" "pane=%7" "trace records pane"
run_hook '{"hook_event_name":"Notification","notification_type":"idle_prompt"}'
assert_file_contains "$TRACE_FILE" "idle_prompt" "trace records no-op events"
assert_file_contains "$TRACE_FILE" "state= " "no-op parses to empty state"

# Trace off -> no file
rm -f "$TRACE_OPT_FILE" "$TRACE_FILE"
run_hook '{"hook_event_name":"Stop"}'
[ ! -f "$TRACE_FILE" ] || fail "trace written while disabled"
