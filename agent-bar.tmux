#!/usr/bin/env bash
# Plugin entry point (TPM runs this, or source it from a run-shell). Installs
# the agent bar on status line 1 and the badge mouse bindings.
set -u

CURRENT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$CURRENT_DIR/lib/options.sh"

# ---- tmux option names, centralized: the side-status names are provisional
# on the tmux fork (upstream may rename them — SIDE_BAR.md); a rename is a
# one-line change here.
SIDE_STATUS_OPT="side-status"
SIDE_FORMAT_OPT="side-status-format"
SIDE_WIDTH_OPT="side-status-width"
SIDE_STYLE_OPT="side-status-style"

line="$(bar_option line 1)"
mode="$(bar_option cross_session inline)"
position="$(bar_option position status)"

# Capability probe: setting the side-status option IS the probe — on stock
# tmux it fails and we fall back to the status-line bar. AGENT_BAR_FORCE
# tells bar-format.sh which layout to emit regardless of the option, so a
# failed probe doesn't leave a vertical format on a horizontal line.
if [ "$position" != "status" ]; then
  if ! tmux set-option -g "$SIDE_STATUS_OPT" "$position" 2>/dev/null; then
    position="status"
  fi
fi
export AGENT_BAR_FORCE_POSITION="$position"

if [ "$position" != "status" ]; then
  # Side mode: claim only side-status options; never touch the status line
  # count, and undo any status-mode format claims from a previous run.
  # side-status-width includes the bar's edge line column, so claim one more
  # than the content width the format is built for. The bar has its own
  # side-status-style rather than inheriting status-style; mirror the
  # status line so the bar keeps matching it.
  tmux set-option -g "$SIDE_WIDTH_OPT" "$(($(bar_option width 24) + 1))" 2>/dev/null || true
  side_style="$(tmux show-options -gv status-style 2>/dev/null || true)"
  if [ -n "$side_style" ]; then
    tmux set-option -g "$SIDE_STYLE_OPT" "$side_style" 2>/dev/null || true
  fi
  tmux set-option -g "${SIDE_FORMAT_OPT}[0]" "$(bash "$CURRENT_DIR/lib/bar-format.sh")"
  tmux set-option -gu "status-format[$line]" 2>/dev/null || true
  tmux set-option -gu "status-format[$((line + 1))]" 2>/dev/null || true
else
  # Status mode: the bar claims line @agent_bar_line (plus the next line in
  # cross_session=line mode). Raise the status count to fit, but leave
  # users already running more lines alone; undo any side-mode claims
  # (harmless no-ops on stock tmux). We never LOWER the status count — the
  # pre-plugin value is unknowable.
  if [ "$mode" = "line" ]; then
    needed=$((line + 2))
  else
    needed=$((line + 1))
  fi
  status="$(tmux show-options -gv status 2>/dev/null || true)"
  case "$status" in
    [0-9]) [ "$status" -ge "$needed" ] || tmux set-option -g status "$needed" ;;
    *) tmux set-option -g status "$needed" ;;
  esac

  tmux set-option -g "status-format[$line]" "$(bash "$CURRENT_DIR/lib/bar-format.sh")"
  if [ "$mode" = "line" ]; then
    tmux set-option -g "status-format[$((line + 1))]" "$(bash "$CURRENT_DIR/lib/bar-format.sh" foreign)"
  else
    tmux set-option -gu "status-format[$((line + 1))]" 2>/dev/null || true
  fi
  tmux set-option -gu "$SIDE_STATUS_OPT" 2>/dev/null || true
  tmux set-option -gu "${SIDE_FORMAT_OPT}[0]" 2>/dev/null || true
  tmux set-option -gu "$SIDE_STYLE_OPT" 2>/dev/null || true
fi

# Mouse bindings. Guards dispatch badge clicks (the bar's line, a range
# naming a pane id); the else-arms REPLAY tmux's default bindings verbatim
# (3.7b key-bindings.c) so non-badge status clicks keep working — a plain
# if-shell with no else eats them silently. Generated as a conf fragment:
# tmux's native {} quoting beats bash escaping for the nested menu.
# @agent_bar_mouse off leaves the mouse keys entirely untouched.
if [ "$(bar_option mouse on)" != "off" ]; then
  # Badge clicks land on the bar's line (or two lines in cross_session=line
  # mode). In side mode there is no status line to key on — the id pattern
  # alone is the guard, which is safe: user| ranges exist only on our
  # surfaces.
  if [ "$position" != "status" ]; then
    on_bar="1"
  elif [ "$mode" = "line" ]; then
    on_bar="#{||:#{==:#{mouse_status_line},$line},#{==:#{mouse_status_line},$((line + 1))}}"
  else
    on_bar="#{==:#{mouse_status_line},$line}"
  fi
  bindings="$CURRENT_DIR/.bindings.generated.conf"
  cat > "$bindings" <<EOF
bind-key -n MouseDown1Status {
  if-shell -F "#{&&:${on_bar},#{m/r:^[%@$][0-9]+\$,#{mouse_status_range}}}" {
    run-shell "$CURRENT_DIR/scripts/jump.sh '#{mouse_status_range}'"
  } {
    switch-client -t=
  }
}
bind-key -n MouseDown3Status {
  if-shell -F "#{&&:${on_bar},#{m/r:^%[0-9]+\$,#{mouse_status_range}}}" {
    display-menu -O -T 'Agent: #{S:#{W:#{P:#{?#{==:#{pane_id},#{mouse_status_range}},#{?#{@agent_name},#{@agent_name},#{@agent_app}},}}}}' -x M -y S \\
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
