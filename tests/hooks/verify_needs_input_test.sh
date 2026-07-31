#!/usr/bin/env bash
# scripts/verify-needs-input.sh: user denials emit NO hook event, so
# needs-input badges are verified against the pane's actual screen — if no
# permission prompt is visible anymore, the badge clears.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-verify-$$"
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

tmux_t new-session -d -s work -x 80 -y 24
tmux_t split-window -d -t work
prompt_pane="$(tmux_t list-panes -t work -F '#{pane_id}' | sed -n '1p')"
quiet_pane="$(tmux_t list-panes -t work -F '#{pane_id}' | sed -n '2p')"

state() { tmux_t show-options -pv -t "$1" @agent_state 2>/dev/null; }
verify() { bash "$ROOT_DIR/scripts/verify-needs-input.sh"; }

screen_shows() {
  tmux_t capture-pane -p -t "$prompt_pane" | grep -q "Do you want"
}
wait_until() {
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    "$@" && return 0
    sleep 0.25
  done
  return 1
}
not() { ! "$@"; }

# Prompt visible on screen -> needs-input is truthful, stays
tmux_t send-keys -t "$prompt_pane" "clear; printf 'Do you want to proceed?\\n  1. Yes\\n  2. No\\n'" Enter
wait_until screen_shows || fail "prompt never appeared on screen"
tmux_t set-option -p -t "$prompt_pane" @agent_state needs-input
verify
assert_eq "needs-input" "$(state "$prompt_pane")" "visible prompt keeps badge"

# Prompt gone from screen -> badge was a lie, clears
tmux_t send-keys -t "$prompt_pane" "clear" Enter
wait_until not screen_shows || fail "prompt never left the screen"
verify
assert_eq "idle" "$(state "$prompt_pane")" "vanished prompt clears badge"

# Panes in other states are never touched
tmux_t set-option -p -t "$quiet_pane" @agent_state running
verify
assert_eq "running" "$(state "$quiet_pane")" "running pane untouched"

# No needs-input panes anywhere -> script exits quietly doing nothing
tmux_t set-option -p -t "$prompt_pane" @agent_state done
verify
assert_eq "done" "$(state "$prompt_pane")" "done pane untouched"
