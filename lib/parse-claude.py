"""Map a Claude Code hook payload to an agent state.

Input: JSON payload in $HOOK_PAYLOAD; event name falls back to argv[1],
then $CLAUDE_HOOK_EVENT_NAME. Output protocol is two lines: state, then
subagent lifecycle event ("start"/"stop" or blank). No output means the
hook should not write state.

Event names and notification types verified against
https://code.claude.com/docs/en/hooks.md (July 2026).
"""

import json
import os
import sys


# Notifications that must not touch state. idle_prompt fires every ~60s while
# Claude waits for input — including while a permission prompt is pending, so
# mapping it to any state would erase a live needs-input badge. Every other
# type (permission_prompt, agent_needs_input, ...) is an attention request and
# falls through to needs-input.
IGNORED_NOTIFICATIONS = {
    "idle_prompt",
    "auth_success",
    "elicitation_complete",
    "elicitation_response",
    "agent_completed",
}


def payload():
    try:
        data = json.loads(os.environ.get("HOOK_PAYLOAD", ""))
    except (json.JSONDecodeError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def event_name(data):
    for candidate in (
        data.get("hook_event_name"),
        sys.argv[1] if len(sys.argv) > 1 else "",
        os.environ.get("CLAUDE_HOOK_EVENT_NAME", ""),
    ):
        if candidate:
            return str(candidate)
    return ""


def parse(data):
    event = event_name(data)
    if event in ("SessionStart", "SessionEnd"):
        return "idle", ""
    if event == "UserPromptSubmit":
        return "running", ""
    if event == "SubagentStart":
        return "running", "start"
    if event == "SubagentStop":
        return "running", "stop"
    if event == "Notification":
        notification_type = str(data.get("notification_type", ""))
        if notification_type in IGNORED_NOTIFICATIONS:
            return "", ""
        # Untyped and unknown-typed notifications are attention requests.
        return "needs-input", ""
    if event == "PermissionRequest":
        return "needs-input", ""
    if event == "Stop":
        return "done", ""
    if event == "StopFailure":
        return "error", ""
    return "", ""


def main():
    state, subagent_event = parse(payload())
    if state:
        print(state)
        print(subagent_event)


if __name__ == "__main__":
    main()
