#!/usr/bin/env bash
# Smoke test that the bar actually draws: an inner tmux with status 2 and our
# format runs inside an outer tmux pane; capturing the outer pane shows the
# inner server's rendered status lines (tmux regress capture pattern).
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

OUTER="agent-bar-outer-$$"
INNER="agent-bar-inner-$$"
tmux_o() { command tmux -L "$OUTER" -f /dev/null "$@"; }
tmux_i() { command tmux -L "$INNER" -f /dev/null "$@"; }
trap 'tmux_o kill-server 2>/dev/null; tmux_i kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT
unset TMUX

tmux_i new-session -d -s work -n api -x 90 -y 24
pane="$(tmux_i display-message -p -t work:api '#{pane_id}')"
tmux_i set-option -g status 2
tmux_i set-option -g status-format[1] "$(bash "$ROOT_DIR/lib/bar-format.sh")"
tmux_i set-option -p -t "$pane" @agent_state needs-input

tmux_o new-session -d -x 90 -y 24
tmux_o send-keys "exec tmux -L '$INNER' attach" Enter

captured=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.5
  captured="$(tmux_o capture-pane -p)"
  case "$captured" in *"? api"*) break ;; esac
done

assert_contains "$captured" "? api" "badge drawn on status line"

# State change redraws without any explicit refresh
tmux_i set-option -p -t "$pane" @agent_state done
updated=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.5
  updated="$(tmux_o capture-pane -p)"
  case "$updated" in *"+ api"*) break ;; esac
done
assert_contains "$updated" "+ api" "redraw on option change"
