#!/usr/bin/env bash
# Hooks run concurrently. A tool event (PostToolUse) that reads the subagent
# count before a SubagentStart/Stop lands and writes after it must not undo
# that event. Real server; the tmux shim lands the subagent event exactly
# between the tool event's read of the count and its write.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-race-$$"
REAL_TMUX="$(command -v tmux)"
tmux_t() { "$REAL_TMUX" -L "$SOCKET" -f /dev/null "$@"; }
trap 'tmux_t kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
# The hook's read of @agent_subagents answers first, then RACE_EVENT runs
# through the hook to completion before the reading hook carries on.
if [ -n "\${RACE_EVENT:-}" ] && [ "\$1" = show-options ] && [[ "\$*" == *@agent_subagents* ]]; then
  "$REAL_TMUX" -L "$SOCKET" -f /dev/null "\$@"
  printf '%s' "\$RACE_EVENT" | RACE_EVENT= bash "$ROOT_DIR/hooks/claude.sh"
  exit 0
fi
exec "$REAL_TMUX" -L "$SOCKET" -f /dev/null "\$@"
SHIM
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"
unset TMUX

tmux_t new-session -d -x 80 -y 24
pane="$(tmux_t display-message -p '#{pane_id}')"
export TMUX_PANE="$pane"

option() { tmux_t show-options -pv -t "$pane" "$1" 2>/dev/null; }

# Runs the tool event, with the subagent event landing mid-write.
tool_event_racing() {
  printf '%s' '{"hook_event_name":"PostToolUse"}' | RACE_EVENT="$1" bash "$ROOT_DIR/hooks/claude.sh"
}

# The last subagent finishes: the tool event must not put the old count
# back and pin "**" until the turn ends.
tmux_t set-option -p -t "$pane" @agent_state subagent-running \; \
  set-option -p -t "$pane" @agent_subagents 1
tool_event_racing '{"hook_event_name":"SubagentStop"}'
assert_eq "0" "$(option @agent_subagents)" "stop's count survives"
assert_eq "running" "$(option @agent_state)" "no subagents left"

# A subagent starts: the tool event must not zero the count, which hides
# "**" and drops that subagent's stop as stale.
tmux_t set-option -p -t "$pane" @agent_state running \; \
  set-option -p -t "$pane" @agent_subagents 0
tool_event_racing '{"hook_event_name":"SubagentStart"}'
assert_eq "1" "$(option @agent_subagents)" "start's count survives"
assert_eq "subagent-running" "$(option @agent_state)" "subagent running"
