#!/usr/bin/env bash
# lib/bar-format.sh prints the status-format[1] string; expanding it against a
# real server must render one clickable badge per non-idle agent pane.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-render-$$"
tmux_t() { command tmux -L "$SOCKET" -f /dev/null "$@"; }
trap 'tmux_t kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT
unset TMUX

tmux_t new-session -d -s work -n api -x 80 -y 24
tmux_t new-session -d -s home -n notes -x 80 -y 24
tmux_t split-window -d -t work:api

agent_pane="$(tmux_t list-panes -t work:api -F '#{pane_id}' | head -1)"
plain_pane="$(tmux_t list-panes -t work:api -F '#{pane_id}' | sed -n '2p')"
home_pane="$(tmux_t list-panes -t home:notes -F '#{pane_id}')"

format="$(bash "$ROOT_DIR/lib/bar-format.sh")"
render() { tmux_t display-message -p "$format"; }

# No agent state anywhere -> empty bar
assert_eq "" "$(render | tr -d ' ')" "empty bar without agents"

# One running agent renders a clickable badge with session:window label
tmux_t set-option -p -t "$agent_pane" @agent_state running
out="$(render)"
assert_contains "$out" "#[range=user|$agent_pane]" "range opens with pane id"
assert_contains "$out" "#[norange]" "range closes"
assert_contains "$out" "work:api" "session:window label"
assert_not_contains "$out" "home:notes" "stateless pane renders nothing"

# States get distinct glyphs
tmux_t set-option -p -t "$agent_pane" @agent_state needs-input
assert_contains "$(render)" "? work:api" "needs-input glyph"
tmux_t set-option -p -t "$agent_pane" @agent_state done
assert_contains "$(render)" "+ work:api" "done glyph"
tmux_t set-option -p -t "$agent_pane" @agent_state error
assert_contains "$(render)" "! work:api" "error glyph"
tmux_t set-option -p -t "$agent_pane" @agent_state subagent-running
assert_contains "$(render)" "** work:api" "subagent glyph"

# idle is invisible
tmux_t set-option -p -t "$agent_pane" @agent_state idle
assert_eq "" "$(render | tr -d ' ')" "idle renders nothing"

# Two agents in different sessions both render, independently clickable
tmux_t set-option -p -t "$agent_pane" @agent_state running
tmux_t set-option -p -t "$home_pane" @agent_state needs-input
out="$(render)"
assert_contains "$out" "#[range=user|$agent_pane]" "first badge range"
assert_contains "$out" "#[range=user|$home_pane]" "second badge range"
assert_contains "$out" "? home:notes" "second badge label"

# A non-active pane with state still renders (P loop, not active-pane shortcut)
tmux_t set-option -p -t "$plain_pane" @agent_state running
tmux_t select-pane -t "$agent_pane"
assert_contains "$(render)" "#[range=user|$plain_pane]" "non-active pane badge"

# Pane title: shown (truncated) when an app or user set one; the default
# hostname title is noise and stays hidden.
tmux_t set-option -p -t "$plain_pane" @agent_state idle
tmux_t select-pane -T "fixing the tests" -t "$agent_pane"
assert_contains "$(render)" "work:api fixing the tests" "set pane title shown"
assert_not_contains "$(render)" "$(hostname)" "default hostname title hidden"

# Session prefix only when foreign: with no client every session is foreign
# (asserted above via work:api); with a client attached to work, work drops
# the prefix and home keeps it.
exec 9> >(command tmux -L "$SOCKET" -f /dev/null -C attach -t work >/dev/null 2>&1)
client=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  client="$(tmux_t list-clients -F '#{client_name}' 2>/dev/null | head -1)"
  [ -n "$client" ] && break
  sleep 0.2
done
[ -n "$client" ] || fail "control client never attached"
attached="$(tmux_t display-message -p -c "$client" "$format")"
exec 9>&-
assert_contains "$attached" "api fixing the tests" "local badge keeps window name"
assert_not_contains "$attached" "work:api" "local session prefix hidden"
assert_contains "$attached" "? home:notes" "foreign session prefix kept"
