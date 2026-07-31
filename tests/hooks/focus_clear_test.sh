#!/usr/bin/env bash
# Navigating to an agent pane acknowledges it: needs-input and done clear to
# idle; running and error persist. Real server, hooks installed by the plugin.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-focus-$$"
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

tmux_t new-session -d -s work -n api -x 80 -y 24
tmux_t split-window -d -t work:api
pane_a="$(tmux_t list-panes -t work:api -F '#{pane_id}' | sed -n '1p')"
pane_b="$(tmux_t list-panes -t work:api -F '#{pane_id}' | sed -n '2p')"

bash "$ROOT_DIR/agent-bar.tmux"

state() { tmux_t show-options -pv -t "$1" @agent_state 2>/dev/null; }

# needs-input on the unfocused pane survives until we select it
tmux_t select-pane -t "$pane_a"
tmux_t set-option -p -t "$pane_b" @agent_state needs-input
assert_eq "needs-input" "$(state "$pane_b")" "state persists while unfocused"
tmux_t select-pane -t "$pane_b"
assert_eq "idle" "$(state "$pane_b")" "needs-input clears on select-pane"

# done clears the same way
tmux_t select-pane -t "$pane_a"
tmux_t set-option -p -t "$pane_b" @agent_state done
tmux_t select-pane -t "$pane_b"
assert_eq "idle" "$(state "$pane_b")" "done clears on select-pane"

# running and error persist through navigation
for persistent in running error; do
  tmux_t select-pane -t "$pane_a"
  tmux_t set-option -p -t "$pane_b" @agent_state "$persistent"
  tmux_t select-pane -t "$pane_b"
  assert_eq "$persistent" "$(state "$pane_b")" "$persistent persists on focus"
done

# Selecting a window clears its active agent pane
tmux_t new-window -t work -n db
done_pane="$(tmux_t list-panes -t work:db -F '#{pane_id}')"
tmux_t set-option -p -t "$done_pane" @agent_state done
tmux_t select-window -t work:api
tmux_t select-window -t work:db
assert_eq "idle" "$(state "$done_pane")" "done clears on select-window"

# A pane with no agent state is untouched (no spurious idle writes)
tmux_t select-pane -t "$pane_a"
assert_eq "" "$(state "$pane_a")" "stateless pane stays stateless"
