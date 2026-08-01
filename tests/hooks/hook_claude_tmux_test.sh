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
