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

# Earlier versions hooked after-select-pane/after-select-window; loading
# this version retires those entries rather than running both.
tmux_t set-hook -g 'after-select-pane[181]' 'display-message stale'
tmux_t set-hook -g 'after-select-window[182]' 'display-message stale'

bash "$ROOT_DIR/agent-bar.tmux"

assert_not_contains "$(tmux_t show-hooks -g after-select-pane)" "[181]" "stale pane hook retired"
assert_not_contains "$(tmux_t show-hooks -g after-select-window)" "[182]" "stale window hook retired"

state() { tmux_t show-options -pv -t "$1" @agent_state 2>/dev/null; }

# pane_b plays the agent. It records no @agent_transcript, so needs-input
# verification never touches it — clearing requires positive evidence.

# needs-input is truthful state: the pane still wants input, so visiting
# it must NOT clear the badge (only answering the prompt does, via events)
tmux_t select-pane -t "$pane_a"
tmux_t set-option -p -t "$pane_b" @agent_state needs-input
assert_eq "needs-input" "$(state "$pane_b")" "state persists while unfocused"
tmux_t select-pane -t "$pane_b"
assert_eq "needs-input" "$(state "$pane_b")" "needs-input survives focus"

# done is an attention flag with no residual truth: visiting clears it
tmux_t select-pane -t "$pane_a"
tmux_t set-option -p -t "$pane_b" @agent_state done
tmux_t select-pane -t "$pane_b"
assert_eq "idle" "$(state "$pane_b")" "done clears on select-pane"

# running, error, and needs-input persist through navigation
for persistent in running error needs-input; do
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

# last-pane (prefix ;) runs no after-select-pane hook, so the plugin
# listens for the active pane changing instead
tmux_t select-window -t work:api
tmux_t select-pane -t "$pane_b"
tmux_t select-pane -t "$pane_a"
tmux_t set-option -p -t "$pane_b" @agent_state done
tmux_t last-pane -t work:api
assert_eq "idle" "$(state "$pane_b")" "done clears on last-pane"

# Focus falling to an agent pane when the active pane closes is a visit too
tmux_t split-window -t "$pane_b"
doomed="$(tmux_t display-message -p -t work:api '#{pane_id}')"
tmux_t set-option -p -t "$pane_b" @agent_state done
tmux_t kill-pane -t "$doomed"
assert_eq "$pane_b" "$(tmux_t display-message -p -t work:api '#{pane_id}')" "focus fell to the agent pane"
assert_eq "idle" "$(state "$pane_b")" "done clears when focus falls to it"

# ...but only in view: an active-pane change in a background window is
# not a visit
tmux_t select-pane -t "$pane_a"
tmux_t select-window -t work:db
tmux_t set-option -p -t "$pane_b" @agent_state done
tmux_t select-pane -t "$pane_b"
assert_eq "done" "$(state "$pane_b")" "background pane change keeps done"
tmux_t select-window -t work:api
assert_eq "idle" "$(state "$pane_b")" "done clears once its window is in view"

# A pane with no agent state is untouched (no spurious idle writes)
tmux_t select-pane -t "$pane_a"
assert_eq "" "$(state "$pane_a")" "stateless pane stays stateless"

# Navigating AWAY from an agent pane must never clear it: only visiting
# the pane itself acknowledges the badge.
tmux_t select-pane -t "$pane_b"
tmux_t set-option -p -t "$pane_b" @agent_state needs-input
tmux_t select-pane -t "$pane_a"
assert_eq "needs-input" "$(state "$pane_b")" "select-pane away keeps badge"
tmux_t select-window -t work:db
assert_eq "needs-input" "$(state "$pane_b")" "select-window away keeps badge"
tmux_t new-session -d -s other -x 80 -y 24
tmux_t switch-client -t other 2>/dev/null || true
assert_eq "needs-input" "$(state "$pane_b")" "session switch keeps badge"
