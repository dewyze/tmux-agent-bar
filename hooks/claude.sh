#!/usr/bin/env bash
# Claude Code hook entry point: payload on stdin (or argv), writes the pane's
# @agent_* user options. Always exits 0 so a failure never disturbs Claude.
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
. "$ROOT_DIR/lib/hook-lib.sh"

resolve_hook_input "$@"

result="$(HOOK_PAYLOAD="$HOOK_PAYLOAD" python3 "$ROOT_DIR/lib/parse-claude.py" "$HOOK_EVENT_ARG")" || exit 0
state="$(printf '%s\n' "$result" | sed -n '1p')"
subagent_event="$(printf '%s\n' "$result" | sed -n '2p')"
transcript="$(printf '%s\n' "$result" | sed -n '3p')"

# Opt-in diagnostics: `tmux set -g @agent_bar_trace /path/to/log` records
# every event (including no-ops) with its parse result.
trace_file="$(tmux show-options -gv @agent_bar_trace 2>/dev/null || true)"
if [ -n "$trace_file" ]; then
  printf '%s pane=%s state=%s sub=%s payload=%s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S')" "${TMUX_PANE:-none}" "$state" \
    "$subagent_event" "$HOOK_PAYLOAD" >> "$trace_file" 2>/dev/null || true
fi

[ -n "$state" ] || exit 0

pane="${TMUX_PANE:-}"
[[ "$pane" =~ ^%[0-9]+$ ]] || exit 0

if [ "$state" = "exit" ]; then
  tmux set-option -pu -t "$pane" @agent_app \; \
    set-option -pu -t "$pane" @agent_state \; \
    set-option -pu -t "$pane" @agent_subagents \; \
    set-option -pu -t "$pane" @agent_updated \; \
    set-option -pu -t "$pane" @agent_transcript \; \
    set-option -pu -t "$pane" @agent_writer_version 2>/dev/null
  exit 0
fi

count="$(tmux show-options -pv -t "$pane" @agent_subagents 2>/dev/null || true)"
[[ "$count" =~ ^[0-9]+$ ]] || count=0

case "$subagent_event" in
  start)
    count=$((count + 1))
    state="subagent-running"
    ;;
  stop)
    # A stop with nothing running is a stale event (e.g. a background agent
    # finishing after Stop already wrote done) — writing would lie.
    [ "$count" -gt 0 ] || exit 0
    count=$((count - 1))
    if [ "$count" -gt 0 ]; then
      state="subagent-running"
    fi
    ;;
  soft)
    if [ "$count" -gt 0 ]; then
      state="subagent-running"
    fi
    ;;
  *)
    # Reset guard: a lost SubagentStop must not pin the pane at
    # subagent-running forever, so terminal events drain the refcount.
    case "$state" in
      running|done|idle) count=0 ;;
    esac
    ;;
esac

write=(set-option -p -t "$pane" @agent_app claude
  \; set-option -p -t "$pane" @agent_state "$state"
  \; set-option -p -t "$pane" @agent_subagents "$count"
  \; set-option -p -t "$pane" @agent_updated "$(date +%s)"
  \; set-option -p -t "$pane" @agent_writer_version "$(cat "$ROOT_DIR/VERSION" 2>/dev/null || printf unknown)")
if [ -n "$transcript" ]; then
  write+=(\; set-option -p -t "$pane" @agent_transcript "$transcript")
fi
tmux "${write[@]}" 2>/dev/null

exit 0
