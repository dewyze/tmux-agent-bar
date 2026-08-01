#!/usr/bin/env bash
# Return the tmux server to a clean state matching this checkout: clear every
# @agent_* pane option and reapply the bar, bindings, and hooks. Use after
# updating the checkout or whenever state looks wrong. Does not touch the
# Claude Code side — update the installed plugin copy with:
#   claude plugin update tmux-agent-bar
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

OPTIONS="@agent_app @agent_state @agent_subagents @agent_updated @agent_transcript @agent_writer_version @agent_schema"

tmux list-panes -a -F '#{pane_id}' 2>/dev/null | while IFS= read -r pane; do
  for option in $OPTIONS; do
    tmux set-option -pu -t "$pane" "$option" 2>/dev/null
  done
done

bash "$ROOT_DIR/agent-bar.tmux"

printf 'reset: cleared agent state on all panes, reapplied bar (checkout version %s)\n' \
  "$(cat "$ROOT_DIR/VERSION" 2>/dev/null || printf unknown)"
printf 'reminder: hooks run from the installed plugin copy; sync it with `claude plugin update tmux-agent-bar` and restart agent sessions\n'
