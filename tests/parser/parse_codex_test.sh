#!/usr/bin/env bash
# parse-codex.py: Codex hook payload -> the line protocol (state, subagent
# event, transcript, asker, session). Payload shapes are from a traced Codex
# CLI 0.167 session.
. "$(dirname "$0")/../testlib.sh"

parse() { printf '%s' "$1" | python3 "$ROOT_DIR/lib/parse-codex.py" "${2:-}"; }
line() { parse "$2" | sed -n "${1}p"; }
state_of() { line 1 "$1"; }
subagent_of() { line 2 "$1"; }
transcript_of() { line 3 "$1"; }
asker_of() { line 4 "$1"; }
session_of() { line 5 "$1"; }

# Lifecycle
assert_eq "idle" "$(state_of '{"hook_event_name":"SessionStart","source":"startup"}')" "startup"
assert_eq "idle" "$(state_of '{"hook_event_name":"SessionStart","source":"resume"}')" "resume"
assert_eq "running" "$(state_of '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}')" "prompt"
assert_eq "done" "$(state_of '{"hook_event_name":"Stop","stop_hook_active":false}')" "stop"
assert_eq "exit" "$(state_of '{"hook_event_name":"SessionEnd","reason":"other"}')" "session end"

# Compaction: SessionStart fires again with source compact and changes
# nothing; a manual /compact is typed at the prompt, so the agent is idle.
assert_eq "" "$(parse '{"hook_event_name":"SessionStart","source":"compact"}')" "compaction restart is a no-op"
assert_eq "idle" "$(state_of '{"hook_event_name":"PostCompact","trigger":"manual"}')" "manual compact"
assert_eq "" "$(parse '{"hook_event_name":"PostCompact","trigger":"auto"}')" "auto compact is a no-op"
assert_eq "" "$(parse '{"hook_event_name":"PreCompact","trigger":"manual"}')" "pre-compact is a no-op"

# Permissions. A denial, like Esc, fires Interrupt: the turn is over and the
# human is at the prompt, with no Stop to follow.
assert_eq "needs-input" "$(state_of '{"hook_event_name":"PermissionRequest","tool_name":"Bash"}')" "permission request"
assert_eq "idle" "$(state_of '{"hook_event_name":"Interrupt"}')" "interrupt"
assert_eq "" "$(subagent_of '{"hook_event_name":"Interrupt"}')" "interrupt is not soft"

# Tools: finished tool calls are soft running; a starting one says nothing
# new (it precedes the permission request it may trigger).
assert_eq "running" "$(state_of '{"hook_event_name":"PostToolUse","tool_name":"Bash"}')" "tool finished"
assert_eq "soft" "$(subagent_of '{"hook_event_name":"PostToolUse","tool_name":"Bash"}')" "tool finished is soft"
assert_eq "" "$(parse '{"hook_event_name":"PreToolUse","tool_name":"Bash"}')" "tool starting is a no-op"

# Subagents
assert_eq "start" "$(subagent_of '{"hook_event_name":"SubagentStart","agent_id":"01a1-5b59"}')" "subagent start"
assert_eq "stop" "$(subagent_of '{"hook_event_name":"SubagentStop","agent_id":"01a1-5b59"}')" "subagent stop"

# Who the event is from
assert_eq "01a1-5b59" "$(asker_of '{"hook_event_name":"PostToolUse","agent_id":"01a1-5b59"}')" "subagent tool"
assert_eq "main" "$(asker_of '{"hook_event_name":"PermissionRequest"}')" "main agent request"

# No transcript is recorded: Codex reports a denial itself, so nothing needs
# to read one, and a subagent's events name the subagent's file.
assert_eq "" "$(transcript_of '{"hook_event_name":"Stop","transcript_path":"/tmp/rollout.jsonl"}')" "no transcript"

# The session, so a late SessionEnd can be matched to it. Subagent events
# carry the parent's session id.
assert_eq "01a1-f748" "$(session_of '{"hook_event_name":"Stop","session_id":"01a1-f748"}')" "session id"
assert_eq "01a1-f748" "$(session_of '{"hook_event_name":"SessionEnd","session_id":"01a1-f748"}')" "session id on exit"

# Unknown events and garbage write nothing
assert_eq "" "$(parse '{"hook_event_name":"PostModelRequest"}')" "unknown event"
assert_eq "" "$(parse 'not json')" "garbage"

# The event name can come from argv
assert_eq "running" "$(printf '{}' | python3 "$ROOT_DIR/lib/parse-codex.py" UserPromptSubmit | sed -n 1p)" "event from argv"
