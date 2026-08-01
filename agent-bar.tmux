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

# The menu must open inside the binding, keeping the live mouse event:
# -x M -y M positions at the click, and tmux's native menu then supports
# both press-drag-release selection and click-then-choose. Routing through
# run-shell loses the event (menu lands at the top edge and dies on button
# release). Formats in the items expand when the menu opens, mouse valid.
tmux bind-key -n MouseDown3Status if-shell -F "$guard" \
  "display-menu -T 'Agent #{mouse_status_range}' -x M -y M \
    'Jump' j \"run-shell \\\"$CURRENT_DIR/scripts/jump.sh '#{mouse_status_range}'\\\"\" \
    'Clear status' c \"set-option -p -t '#{mouse_status_range}' @agent_state idle\" \
    '' \
    'Kill pane' x \"confirm-before -p 'Kill pane #{mouse_status_range}? (y/n)' \\\"kill-pane -t '#{mouse_status_range}'\\\"\""

# Navigating to an agent pane acknowledges done (a seen "+" has no residual
# truth). needs-input persists — the pane still wants input until an event
# says otherwise; running/error persist too. Navigation hooks fire on the
# commands themselves, unlike pane-focus-in which needs terminal focus
# events. Array indices keep clear of user-defined hooks on the same events.
acknowledge='if-shell -F "#{==:#{@agent_state},done}" "set-option -p @agent_state idle"'
# Denials emit no hook event, so needs-input badges are re-verified against
# the pane's actual screen on navigation — but only when one exists (the
# format guard keeps steady-state navigation free of process spawns).
any_needs_input='#{S:#{W:#{P:#{?#{==:#{@agent_state},needs-input},x,}}}}'
verify="if-shell -F \"$any_needs_input\" \"run-shell -b '$CURRENT_DIR/scripts/verify-needs-input.sh'\""
tmux set-hook -g 'after-select-pane[181]' "$acknowledge ; $verify"
tmux set-hook -g 'after-select-window[182]' "$acknowledge ; $verify"
tmux set-hook -g 'client-session-changed[183]' "$acknowledge ; $verify"
