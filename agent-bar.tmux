#!/usr/bin/env bash
# Plugin entry point (TPM runs this, or source it from a run-shell). Installs
# the agent bar on status line 1 and the badge mouse bindings.
set -u

CURRENT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$CURRENT_DIR/lib/options.sh"

# The bar claims status line @agent_bar_line (default 1). Raise the status
# line count to fit it, but leave users already running more lines alone.
line="$(bar_option line 1)"
needed=$((line + 1))
status="$(tmux show-options -gv status 2>/dev/null || true)"
case "$status" in
  [0-9]) [ "$status" -ge "$needed" ] || tmux set-option -g status "$needed" ;;
  *) tmux set-option -g status "$needed" ;;
esac

tmux set-option -g "status-format[$line]" "$(bash "$CURRENT_DIR/lib/bar-format.sh")"

# Mouse bindings. Guards dispatch badge clicks (the bar's line, a range
# naming a pane id); the else-arms REPLAY tmux's default bindings verbatim
# (3.7b key-bindings.c) so non-badge status clicks keep working — a plain
# if-shell with no else eats them silently. Generated as a conf fragment:
# tmux's native {} quoting beats bash escaping for the nested menu.
# @agent_bar_mouse off leaves the mouse keys entirely untouched.
if [ "$(bar_option mouse on)" != "off" ]; then
  bindings="$CURRENT_DIR/.bindings.generated.conf"
  cat > "$bindings" <<EOF
bind-key -n MouseDown1Status {
  if-shell -F "#{&&:#{==:#{mouse_status_line},$line},#{m/r:^%[0-9]+\$,#{mouse_status_range}}}" {
    run-shell "$CURRENT_DIR/scripts/jump.sh '#{mouse_status_range}'"
  } {
    switch-client -t=
  }
}
bind-key -n MouseDown3Status {
  if-shell -F "#{&&:#{==:#{mouse_status_line},$line},#{m/r:^%[0-9]+\$,#{mouse_status_range}}}" {
    display-menu -T 'Agent #{mouse_status_range}' -x M -y M \\
      'Jump' j "run-shell \\"$CURRENT_DIR/scripts/jump.sh '#{mouse_status_range}'\\"" \\
      'Clear status' c "set-option -p -t '#{mouse_status_range}' @agent_state idle" \\
      'Rename' n "command-prompt -p 'Agent name:' { set-option -p -t '#{mouse_status_range}' @agent_name '%%' }" \\
      '' \\
      'Kill pane' x "confirm-before -p 'Kill pane #{mouse_status_range}? (y/n)' \\"kill-pane -t '#{mouse_status_range}'\\""
  } {
    display-menu -t= -xW -yW -T '#[align=centre]#{window_index}:#{window_name}' \\
      '#{?#{>:#{session_windows},1},,-}Swap Left' 'l' {swap-window -t:-1} \\
      '#{?#{>:#{session_windows},1},,-}Swap Right' 'r' {swap-window -t:+1} \\
      '#{?pane_marked_set,,-}Swap Marked' 's' {swap-window} \\
      '' \\
      'Kill' 'X' {kill-window} \\
      'Respawn' 'R' {respawn-window -k} \\
      '#{?pane_marked,Unmark,Mark}' 'm' {select-pane -m} \\
      'Rename' 'n' {command-prompt -FI "#W" {rename-window -t '#{window_id}' -- '%%'}} \\
      '' \\
      'New After' 'w' {new-window -a} \\
      'New At End' 'W' {new-window}
  }
}
EOF
  tmux source-file "$bindings"
fi

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
