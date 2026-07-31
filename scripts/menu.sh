#!/usr/bin/env bash
# Context menu for an agent badge. Args: pane_id mouse_x mouse_y — all
# pre-expanded by the mouse binding so no format context is needed here.
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

pane="${1:-}"
x="${2:-}"
y="${3:-}"
[[ "$pane" =~ ^%[0-9]+$ ]] || exit 1
[[ "$x" =~ ^[0-9]+$ ]] || exit 1
[[ "$y" =~ ^[0-9]+$ ]] || exit 1

exec tmux display-menu -T "Agent $pane" -x "$x" -y "$y" \
  "Jump" j "run-shell '$SCRIPT_DIR/jump.sh $pane'" \
  "Clear status" c "set-option -p -t $pane @agent_state idle" \
  "" \
  "Kill pane" x "confirm-before -p 'Kill pane $pane? (y/n)' 'kill-pane -t $pane'"
