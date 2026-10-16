#!/usr/bin/env bash
# parse-claude.py: Claude Code hook payload -> "state\nsubagent_event" protocol.
. "$(dirname "$0")/../testlib.sh"

parse() {
  HOOK_PAYLOAD="$1" python3 "$ROOT_DIR/lib/parse-claude.py" "${2:-}"
}

state_of() { parse "$1" "${2:-}" | sed -n '1p'; }
subagent_of() { parse "$1" "${2:-}" | sed -n '2p'; }
transcript_of() { parse "$1" "${2:-}" | sed -n '3p'; }

# Lifecycle events. SessionStart -> idle (agent present, waiting); a live
# idle agent renders a dim badge. SessionEnd -> exit: the agent is GONE,
# which removes the badge entirely rather than dimming it.
assert_eq "idle" "$(state_of '{"hook_event_name":"SessionStart"}')" "SessionStart"
assert_eq "exit" "$(state_of '{"hook_event_name":"SessionEnd"}')" "SessionEnd"
assert_eq "running" "$(state_of '{"hook_event_name":"UserPromptSubmit"}')" "UserPromptSubmit"
assert_eq "done" "$(state_of '{"hook_event_name":"Stop"}')" "Stop"

# Compaction fires SessionStart too, but it changes nothing about what the
# agent is doing: idle compaction must not demote an unseen done, and
# mid-turn compaction must not dim a running agent. It writes nothing.
assert_eq "" "$(parse '{"hook_event_name":"SessionStart","source":"compact"}')" "compaction is a no-op"
assert_eq "idle" "$(state_of '{"hook_event_name":"SessionStart","source":"startup"}')" "startup is idle"
assert_eq "idle" "$(state_of '{"hook_event_name":"SessionStart","source":"clear"}')" "clear is idle"

# The idle_prompt nudge fires every ~60s while Claude waits for input —
# including while a permission prompt is pending. It must write NOTHING:
# mapping it to idle erases a live needs-input badge.
assert_eq "" "$(parse '{"hook_event_name":"Notification","notification_type":"idle_prompt"}')" "idle_prompt is a no-op"
assert_eq "needs-input" "$(state_of '{"hook_event_name":"Notification","notification_type":"permission_prompt"}')" "permission_prompt"
assert_eq "needs-input" "$(state_of '{"hook_event_name":"Notification","notification_type":"agent_needs_input"}')" "agent_needs_input"
assert_eq "needs-input" "$(state_of '{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}')" "untyped notification"
assert_eq "needs-input" "$(state_of '{"hook_event_name":"PermissionRequest"}')" "PermissionRequest"

# Benign notification types must not write state at all
assert_eq "" "$(parse '{"hook_event_name":"Notification","notification_type":"auth_success"}')" "auth_success"
assert_eq "" "$(parse '{"hook_event_name":"Notification","notification_type":"elicitation_complete"}')" "elicitation_complete"
assert_eq "" "$(parse '{"hook_event_name":"Notification","notification_type":"elicitation_response"}')" "elicitation_response"

# After a usage-limit pause, Claude continuing on its own is not a request
# for attention. Waiting for Enter after a long sleep still is.
assert_eq "" "$(parse '{"hook_event_name":"Notification","notification_type":"quota_auto_resume_fired"}')" "quota_auto_resume_fired"
assert_eq "needs-input" "$(state_of '{"hook_event_name":"Notification","notification_type":"quota_auto_resume_stale"}')" "quota_auto_resume_stale"
# Giving up on the wait is the only signal when a queued continuation is
# dropped after its prompt already wrote running: it must stay needs-input.
assert_eq "needs-input" "$(state_of '{"hook_event_name":"Notification","notification_type":"quota_auto_resume_disabled"}')" "quota_auto_resume_disabled"

# Turn-died-on-API-error is the one clean error signal
assert_eq "error" "$(state_of '{"hook_event_name":"StopFailure"}')" "StopFailure"

# Subagents: state stays running, second line carries the lifecycle event
assert_eq "running" "$(state_of '{"hook_event_name":"SubagentStart"}')" "SubagentStart state"
assert_eq "start" "$(subagent_of '{"hook_event_name":"SubagentStart"}')" "SubagentStart event"
assert_eq "running" "$(state_of '{"hook_event_name":"SubagentStop"}')" "SubagentStop state"
assert_eq "stop" "$(subagent_of '{"hook_event_name":"SubagentStop"}')" "SubagentStop event"
assert_eq "" "$(subagent_of '{"hook_event_name":"Stop"}')" "Stop has no subagent event"

# PostToolUse means work is executing: running, but "soft" — it must not
# stomp subagent bookkeeping (it fires constantly during subagent turns).
assert_eq "running" "$(state_of '{"hook_event_name":"PostToolUse"}')" "PostToolUse state"
assert_eq "soft" "$(subagent_of '{"hook_event_name":"PostToolUse"}')" "PostToolUse soft marker"

# Tool failures and denials also mean Claude is processing again — the
# truthful exit from needs-input whichever way the prompt was answered.
# Soft running, NOT error: routine tool failures happen mid-run constantly.
assert_eq "running" "$(state_of '{"hook_event_name":"PostToolUseFailure"}')" "PostToolUseFailure state"
assert_eq "soft" "$(subagent_of '{"hook_event_name":"PostToolUseFailure"}')" "PostToolUseFailure soft"
assert_eq "running" "$(state_of '{"hook_event_name":"PermissionDenied"}')" "PermissionDenied state"
assert_eq "soft" "$(subagent_of '{"hook_event_name":"PermissionDenied"}')" "PermissionDenied soft"

# Unknown or malformed input -> empty output, exit 0 (hook becomes a no-op)
assert_eq "" "$(parse '{"hook_event_name":"PreToolUse"}')" "unknown event"
assert_eq "" "$(parse 'not json')" "malformed payload"
assert_eq "" "$(parse '')" "empty payload"
assert_eq "" "$(parse '[1,2]')" "non-dict payload"

# transcript_path passes through on line 3 (empty when absent) so the hook
# can record it for needs-input verification
assert_eq "/tmp/t.jsonl" "$(transcript_of '{"hook_event_name":"Stop","transcript_path":"/tmp/t.jsonl"}')" "transcript passthrough"
assert_eq "" "$(transcript_of '{"hook_event_name":"Stop"}')" "no transcript -> empty line"

# Event name fallbacks: argv, then CLAUDE_HOOK_EVENT_NAME env
assert_eq "done" "$(state_of '{}' 'Stop')" "argv fallback"
assert_eq "done" "$(HOOK_PAYLOAD='{}' CLAUDE_HOOK_EVENT_NAME='Stop' python3 "$ROOT_DIR/lib/parse-claude.py" | sed -n '1p')" "env fallback"
