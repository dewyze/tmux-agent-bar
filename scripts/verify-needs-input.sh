#!/usr/bin/env bash
# User denials emit no Claude Code hook event, so needs-input badges can go
# stale. For every needs-input pane, check the visible screen: if no
# permission prompt is showing anymore, the badge is a lie — clear it.
# (If the agent is actually running again, the next PostToolUse corrects
# idle to running within seconds.)
set -u

PROMPT_PATTERN='Do you want|1\. Yes|❯ 1'

tmux list-panes -a -f '#{==:#{@agent_state},needs-input}' -F '#{pane_id}' 2>/dev/null |
while IFS= read -r pane; do
  if ! tmux capture-pane -p -t "$pane" 2>/dev/null | grep -qE "$PROMPT_PATTERN"; then
    tmux set-option -p -t "$pane" @agent_state idle 2>/dev/null
  fi
done

exit 0
