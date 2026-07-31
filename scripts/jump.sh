#!/usr/bin/env bash
# Jump the current client to an agent's pane: session, window, pane.
set -u

pane="${1:-}"
[[ "$pane" =~ ^%[0-9]+$ ]] || exit 1

exec tmux switch-client -t "$pane" \; \
  select-window -t "$pane" \; \
  select-pane -t "$pane"
