#!/usr/bin/env bash
# Plugin entry point (TPM runs this, or source it from a run-shell). Installs
# the agent bar on status line 1 and the badge mouse bindings.
set -u

CURRENT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

# The bar needs a second status line; raise 'on'/'off' to 2 but leave users
# already running more lines alone (the bar still claims line index 1).
status="$(tmux show-options -gv status 2>/dev/null || true)"
case "$status" in
  3|4|5) ;;
  *) tmux set-option -g status 2 ;;
esac

tmux set-option -g status-format[1] "$(bash "$CURRENT_DIR/lib/bar-format.sh")"

# Badge clicks only: line 1 and a range naming a pane id. Everything else
# falls through to whatever the user has bound.
guard='#{&&:#{==:#{mouse_status_line},1},#{m/r:^%[0-9]+$,#{mouse_status_range}}}'

tmux bind-key -n MouseDown1Status if-shell -F "$guard" \
  "run-shell \"$CURRENT_DIR/scripts/jump.sh '#{mouse_status_range}'\""

tmux bind-key -n MouseDown3Status if-shell -F "$guard" \
  "run-shell \"$CURRENT_DIR/scripts/menu.sh '#{mouse_status_range}' '#{mouse_x}' '#{mouse_y}'\""

# Navigating to an agent pane acknowledges it: needs-input/done clear to
# idle; running/error persist. Navigation hooks fire on the commands
# themselves, unlike pane-focus-in which needs terminal focus events.
# Array indices keep clear of user-defined hooks on the same events.
acknowledge='if-shell -F "#{||:#{==:#{@agent_state},needs-input},#{==:#{@agent_state},done}}" "set-option -p @agent_state idle"'
tmux set-hook -g 'after-select-pane[181]' "$acknowledge"
tmux set-hook -g 'after-select-window[182]' "$acknowledge"
tmux set-hook -g 'client-session-changed[183]' "$acknowledge"
