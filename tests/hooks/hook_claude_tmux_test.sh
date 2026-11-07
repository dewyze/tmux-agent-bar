#!/usr/bin/env bash
# End-to-end against a real tmux server on a private socket: fixture payloads
# in, pane user options out. A PATH shim routes `tmux` to the test server.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-test-$$"
REAL_TMUX="$(command -v tmux)"
tmux_t() { "$REAL_TMUX" -L "$SOCKET" -f /dev/null "$@"; }
trap 'tmux_t kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" -f /dev/null "\$@"
SHIM
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"
unset TMUX

tmux_t new-session -d -x 80 -y 24
pane="$(tmux_t display-message -p '#{pane_id}')"
export TMUX_PANE="$pane"

run_hook() {
  printf '%s' "$1" | bash "$ROOT_DIR/hooks/claude.sh"
}

option() { tmux_t show-options -pv -t "$pane" "$1" 2>/dev/null; }

# Full lifecycle: running -> needs-input -> done
run_hook '{"hook_event_name":"UserPromptSubmit"}'
assert_eq "running" "$(option @agent_state)" "running"
assert_eq "claude" "$(option @agent_app)" "app"
assert_eq "1" "$(option @agent_schema)" "schema version"

run_hook '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
assert_eq "needs-input" "$(option @agent_state)" "needs-input"

run_hook '{"hook_event_name":"Stop"}'
assert_eq "done" "$(option @agent_state)" "done"

# Subagent lifecycle against real option storage
run_hook '{"hook_event_name":"UserPromptSubmit"}'
run_hook '{"hook_event_name":"SubagentStart"}'
run_hook '{"hook_event_name":"SubagentStart"}'
assert_eq "subagent-running" "$(option @agent_state)" "two subagents"
assert_eq "2" "$(option @agent_subagents)" "refcount 2"
run_hook '{"hook_event_name":"SubagentStop"}'
assert_eq "subagent-running" "$(option @agent_state)" "one subagent left"
run_hook '{"hook_event_name":"SubagentStop"}'
assert_eq "running" "$(option @agent_state)" "back to running"
assert_eq "0" "$(option @agent_subagents)" "refcount drained"

# A second pane's state is independent
tmux_t split-window -d
other="$(tmux_t list-panes -F '#{pane_id}' | grep -v "^$pane\$" | head -1)"
printf '%s' '{"hook_event_name":"UserPromptSubmit"}' | TMUX_PANE="$other" bash "$ROOT_DIR/hooks/claude.sh"
assert_eq "running" "$(tmux_t show-options -pv -t "$other" @agent_state)" "other pane running"
assert_eq "running" "$(option @agent_state)" "first pane untouched"

# SessionEnd wipes the pane's agent options entirely
run_hook '{"hook_event_name":"SessionEnd"}'
assert_eq "" "$(option @agent_state)" "state unset after SessionEnd"
assert_eq "" "$(option @agent_app)" "app unset after SessionEnd"
assert_eq "running" "$(tmux_t show-options -pv -t "$other" @agent_state)" "other pane survives"

# A payload past the exec size limit (1MB on macOS, 128KB per variable on
# Linux) still lands: PostCompact carries the whole compaction summary, and
# PostToolUse the whole tool result.
big="$(python3 -c 'import json; print(json.dumps({"hook_event_name": "PostCompact", "trigger": "manual", "compact_summary": "x" * 1100000}))')"
tmux_t set-option -p -t "$pane" @agent_state running
run_hook "$big"
assert_eq "idle" "$(option @agent_state)" "oversized payload still parsed"

# A payload that arrives after the hook has started (a loaded machine) still
# lands.
tmux_t set-option -p -t "$pane" @agent_state running
{ sleep 0.3; printf '%s' '{"hook_event_name":"Stop"}'; } | bash "$ROOT_DIR/hooks/claude.sh"
assert_eq "done" "$(option @agent_state)" "late payload still parsed"

# macOS runs the hook under /bin/bash 3.2 when no newer bash is first on
# PATH. A bash-4+ timestamp form once wrote an empty @agent_updated there,
# which needs-input verification depends on.
tmux_t set-option -pu -t "$pane" @agent_updated
printf '%s' '{"hook_event_name":"Stop"}' | /bin/bash "$ROOT_DIR/hooks/claude.sh"
case "$(option @agent_updated)" in
  ''|*[!0-9]*) fail "/bin/bash wrote @agent_updated [$(option @agent_updated)]" ;;
esac

# Run from inside hooks/, $0 has no directory part; the hook still finds
# its library.
tmux_t set-option -p -t "$pane" @agent_state idle
(cd "$ROOT_DIR/hooks" && printf '%s' '{"hook_event_name":"UserPromptSubmit"}' | bash claude.sh)
assert_eq "running" "$(option @agent_state)" "hook invoked by bare name"
