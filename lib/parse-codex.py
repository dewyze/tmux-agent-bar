"""Map a Codex CLI hook payload to an agent state.

Input: JSON payload on stdin; event name falls back to argv[1]. Output
protocol is five lines: state, subagent lifecycle event
("start"/"stop"/"soft" or blank), the transcript path (always blank, see
main), who the event is from (a subagent's id or "main"), then the session
id. No output means the hook should not write state.

Event names and payload fields verified against a traced Codex CLI 0.167
session (November 2026) and https://developers.openai.com/codex/hooks.
"""

import json
import sys


def payload():
    try:
        data = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def event_name(data):
    return str(data.get("hook_event_name") or (sys.argv[1] if len(sys.argv) > 1 else ""))


def parse(data, event):
    if event == "SessionStart":
        # Fires again after a compaction, which changes nothing about what
        # the agent is doing.
        if data.get("source") == "compact":
            return "", ""
        return "idle", ""
    if event == "SessionEnd":
        # Not a state: the hook unsets the pane's options. Codex sends this
        # up to a minute after the session closes, so the writer matches it
        # to the session on the pane (the fifth line).
        return "exit", ""
    if event == "UserPromptSubmit":
        return "running", ""
    if event == "PostToolUse":
        # "soft" because these fire during subagent turns and must not
        # disturb their bookkeeping. PreToolUse is not mapped: it precedes
        # the permission request it may trigger and says nothing new.
        return "running", "soft"
    if event == "PermissionRequest":
        return "needs-input", ""
    if event == "Interrupt":
        # Esc, or denying a permission request: the turn is over with no
        # Stop to follow, and the human is at the prompt.
        return "idle", ""
    if event == "PostCompact":
        # A manual /compact is typed at the prompt; auto-compaction says
        # nothing about what the agent is doing.
        if data.get("trigger") == "manual":
            return "idle", ""
        return "", ""
    if event == "SubagentStart":
        return "running", "start"
    if event == "SubagentStop":
        return "running", "stop"
    if event == "Stop":
        return "done", ""
    return "", ""


def main():
    data = payload()
    state, subagent_event = parse(data, event_name(data))
    if state:
        print(state)
        print(subagent_event)
        # No transcript: Codex reports a denial itself (Interrupt), so
        # nothing needs to read one, and a subagent's events name the
        # subagent's file, not the session's.
        print("")
        print(str(data.get("agent_id") or "main"))
        print(str(data.get("session_id", "")))


if __name__ == "__main__":
    main()
