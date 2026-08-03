#!/usr/bin/env bash
# Jump the current client to a bar target: %pane (session, window, pane),
# @window (that window, its own last-active pane), or $session (that
# session's current window).
set -u

target="${1:-}"
case "$target" in
  %*)
    [[ "$target" =~ ^%[0-9]+$ ]] || exit 1
    exec tmux switch-client -t "$target" \; \
      select-window -t "$target" \; \
      select-pane -t "$target"
    ;;
  @*)
    [[ "$target" =~ ^@[0-9]+$ ]] || exit 1
    exec tmux switch-client -t "$target" \; \
      select-window -t "$target"
    ;;
  \$*)
    [[ "$target" =~ ^\$[0-9]+$ ]] || exit 1
    exec tmux switch-client -t "$target"
    ;;
  *)
    exit 1
    ;;
esac
