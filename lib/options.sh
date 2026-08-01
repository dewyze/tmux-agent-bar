# Option seam: every user-visible knob reads @agent_bar_<name> with a
# default. Options are read at build/load time (bar-format.sh, agent-bar.tmux)
# — change an option, re-run agent-bar.tmux (or scripts/reset.sh) to apply.
# Source, don't execute.

bar_option() {
  local value
  value="$(tmux show-options -gv "@agent_bar_$1" 2>/dev/null || true)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$2"
  fi
}
