#!/usr/bin/env bash
# A "?" belongs to the agent that asked: the main agent or one subagent. Only
# that agent's activity clears it; other agents working in the same pane leave
# it alone. Real tmux on a private socket, payloads shaped like Claude's
# (subagent events carry agent_id, the main agent's do not).
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-blocked-$$"
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

run_hook() { printf '%s' "$1" | bash "$ROOT_DIR/hooks/claude.sh"; }
state() { tmux_t show-options -pv -t "$pane" @agent_state 2>/dev/null; }
count() { tmux_t show-options -pv -t "$pane" @agent_subagents 2>/dev/null; }

# Two subagents running; subagent a1 asks for permission.
two_subagents_a1_asks() {
  run_hook '{"hook_event_name":"UserPromptSubmit"}'
  run_hook '{"hook_event_name":"SubagentStart","agent_id":"a1"}'
  run_hook '{"hook_event_name":"SubagentStart","agent_id":"b2"}'
  run_hook '{"hook_event_name":"PermissionRequest","agent_id":"a1","tool_name":"Bash"}'
  assert_eq "needs-input" "$(state)" "a1 asks"
}

# Another subagent's tools, a new subagent, and another subagent finishing
# all leave the "?" up, and the count still follows them.
two_subagents_a1_asks
run_hook '{"hook_event_name":"PostToolUse","agent_id":"b2"}'
assert_eq "needs-input" "$(state)" "another subagent's tool"
run_hook '{"hook_event_name":"PostToolUseFailure","agent_id":"b2"}'
assert_eq "needs-input" "$(state)" "another subagent's failed tool"
run_hook '{"hook_event_name":"PostToolUse"}'
assert_eq "needs-input" "$(state)" "the main agent's tool"
run_hook '{"hook_event_name":"SubagentStart","agent_id":"c3"}'
assert_eq "needs-input" "$(state)" "a new subagent"
assert_eq "3" "$(count)" "the new subagent is counted"
run_hook '{"hook_event_name":"SubagentStop","agent_id":"b2"}'
assert_eq "needs-input" "$(state)" "another subagent finishing"
assert_eq "2" "$(count)" "the finished subagent is counted"

# The asker's own tool clears it.
run_hook '{"hook_event_name":"PostToolUse","agent_id":"a1"}'
assert_eq "subagent-running" "$(state)" "the asker's tool clears"

# The asker finishing clears it.
two_subagents_a1_asks
run_hook '{"hook_event_name":"SubagentStop","agent_id":"a1"}'
assert_eq "subagent-running" "$(state)" "the asker finishing clears"

# The permission notification that follows a request names nobody: it must
# not hand the "?" to the main agent.
two_subagents_a1_asks
run_hook '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
run_hook '{"hook_event_name":"PostToolUse"}'
assert_eq "needs-input" "$(state)" "notification keeps the asker"
run_hook '{"hook_event_name":"PostToolUse","agent_id":"a1"}'
assert_eq "subagent-running" "$(state)" "the asker still clears after a notification"

# The main agent asks: subagents leave it alone, its own tool clears it.
run_hook '{"hook_event_name":"UserPromptSubmit"}'
run_hook '{"hook_event_name":"SubagentStart","agent_id":"a1"}'
run_hook '{"hook_event_name":"PermissionRequest","tool_name":"Bash"}'
run_hook '{"hook_event_name":"PostToolUse","agent_id":"a1"}'
assert_eq "needs-input" "$(state)" "a subagent's tool while the main agent asks"
run_hook '{"hook_event_name":"PostToolUse"}'
assert_eq "subagent-running" "$(state)" "the main agent's tool clears its own"

# A notification on its own (nobody asked first) belongs to the main agent.
run_hook '{"hook_event_name":"UserPromptSubmit"}'
run_hook '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
run_hook '{"hook_event_name":"PostToolUse"}'
assert_eq "running" "$(state)" "a lone notification clears on the main agent's tool"

# A new prompt and the end of the turn clear it, whoever asked.
two_subagents_a1_asks
run_hook '{"hook_event_name":"UserPromptSubmit"}'
assert_eq "running" "$(state)" "a new prompt clears"
two_subagents_a1_asks
run_hook '{"hook_event_name":"Stop"}'
assert_eq "done" "$(state)" "the end of the turn clears"

# A "?" with no recorded asker (another writer, or set before this was
# tracked) clears on any activity, as before.
run_hook '{"hook_event_name":"UserPromptSubmit"}'
tmux_t set-option -pu -t "$pane" @agent_asker
tmux_t set-option -p -t "$pane" @agent_state needs-input
run_hook '{"hook_event_name":"PostToolUse","agent_id":"b2"}'
assert_eq "running" "$(state)" "no asker recorded"

# SessionEnd removes the asker with everything else.
two_subagents_a1_asks
run_hook '{"hook_event_name":"SessionEnd"}'
assert_eq "" "$(tmux_t show-options -pv -t "$pane" @agent_asker 2>/dev/null)" "asker unset on exit"
