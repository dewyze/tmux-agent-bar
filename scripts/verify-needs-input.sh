#!/usr/bin/env bash
# User denials emit no Claude Code hook event, so needs-input badges can go
# stale. The agent's transcript is the truth: any entry newer than the badge
# means the prompt was answered — clear it (a next PostToolUse corrects idle
# to running within seconds if the agent kept working). No transcript, no
# clearing: badges only fall to positive evidence, so agents that don't
# record @agent_transcript are never wrongly cleared.
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

tmux list-panes -a -f '#{==:#{@agent_state},needs-input}' -F '#{pane_id}' 2>/dev/null |
while IFS= read -r pane; do
  transcript="$(tmux show-options -pv -t "$pane" @agent_transcript 2>/dev/null || true)"
  updated="$(tmux show-options -pv -t "$pane" @agent_updated 2>/dev/null || true)"
  [ -n "$transcript" ] && [ -n "$updated" ] || continue
  # Compare-and-set: clear only the badge that was checked. A hook write
  # that landed meanwhile (a fresh prompt, the agent resuming) wins.
  if python3 "$ROOT_DIR/lib/transcript-progressed.py" "$transcript" "$updated"; then
    tmux if-shell -F -t "$pane" \
      "#{&&:#{==:#{@agent_state},needs-input},#{==:#{@agent_updated},$updated}}" \
      "set-option -p -t $pane @agent_state idle" 2>/dev/null
  fi
done

exit 0
