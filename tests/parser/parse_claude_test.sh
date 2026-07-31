#!/usr/bin/env bash
# parse-claude.py: Claude Code hook payload -> "state\nsubagent_event" protocol.
. "$(dirname "$0")/../testlib.sh"

parse() {
  HOOK_PAYLOAD="$1" python3 "$ROOT_DIR/lib/parse-claude.py" "${2:-}"
}

state_of() { parse "$1" "${2:-}" | sed -n '1p'; }
subagent_of() { parse "$1" "${2:-}" | sed -n '2p'; }

# Lifecycle events
assert_eq "idle" "$(state_of '{"hook_event_name":"SessionStart"}')" "SessionStart"
assert_eq "idle" "$(state_of '{"hook_event_name":"SessionEnd"}')" "SessionEnd"
assert_eq "running" "$(state_of '{"hook_event_name":"UserPromptSubmit"}')" "UserPromptSubmit"
assert_eq "done" "$(state_of '{"hook_event_name":"Stop"}')" "Stop"

# Notifications: the idle_prompt nudge must NOT read as needs-input
assert_eq "idle" "$(state_of '{"hook_event_name":"Notification","notification_type":"idle_prompt"}')" "idle_prompt"
assert_eq "needs-input" "$(state_of '{"hook_event_name":"Notification","notification_type":"permission_prompt"}')" "permission_prompt"
assert_eq "needs-input" "$(state_of '{"hook_event_name":"Notification","notification_type":"agent_needs_input"}')" "agent_needs_input"
assert_eq "needs-input" "$(state_of '{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}')" "untyped notification"
assert_eq "needs-input" "$(state_of '{"hook_event_name":"PermissionRequest"}')" "PermissionRequest"

# Benign notification types must not write state at all
assert_eq "" "$(parse '{"hook_event_name":"Notification","notification_type":"auth_success"}')" "auth_success"
assert_eq "" "$(parse '{"hook_event_name":"Notification","notification_type":"elicitation_complete"}')" "elicitation_complete"
assert_eq "" "$(parse '{"hook_event_name":"Notification","notification_type":"elicitation_response"}')" "elicitation_response"

# Turn-died-on-API-error is the one clean error signal
assert_eq "error" "$(state_of '{"hook_event_name":"StopFailure"}')" "StopFailure"

# Subagents: state stays running, second line carries the lifecycle event
assert_eq "running" "$(state_of '{"hook_event_name":"SubagentStart"}')" "SubagentStart state"
assert_eq "start" "$(subagent_of '{"hook_event_name":"SubagentStart"}')" "SubagentStart event"
assert_eq "running" "$(state_of '{"hook_event_name":"SubagentStop"}')" "SubagentStop state"
assert_eq "stop" "$(subagent_of '{"hook_event_name":"SubagentStop"}')" "SubagentStop event"
assert_eq "" "$(subagent_of '{"hook_event_name":"Stop"}')" "Stop has no subagent event"

# Unknown or malformed input -> empty output, exit 0 (hook becomes a no-op)
assert_eq "" "$(parse '{"hook_event_name":"PreToolUse"}')" "unknown event"
assert_eq "" "$(parse 'not json')" "malformed payload"
assert_eq "" "$(parse '')" "empty payload"
assert_eq "" "$(parse '[1,2]')" "non-dict payload"

# Event name fallbacks: argv, then CLAUDE_HOOK_EVENT_NAME env
assert_eq "done" "$(state_of '{}' 'Stop')" "argv fallback"
assert_eq "done" "$(HOOK_PAYLOAD='{}' CLAUDE_HOOK_EVENT_NAME='Stop' python3 "$ROOT_DIR/lib/parse-claude.py" | sed -n '1p')" "env fallback"
