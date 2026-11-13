#!/usr/bin/env bash
# Codex end to end against a real tmux server on a private socket: payloads
# shaped like a traced Codex CLI session in, pane user options out.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-codex-$$"
REAL_TMUX="$(command -v tmux)"
tmux_t() { "$REAL_TMUX" -L "$SOCKET" -f /dev/null "$@"; }
trap 'tmux_t kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" -f /dev/null "\$@"
SHIM
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"
unset TMUX

# Codex runs a hook as a child of its own process in the pane, so the hook's
# parent is on the pane's terminal. Here the pane runs a loop that plays
# that part: each line on `go` runs the hook on `payload`.
mkfifo "$TEST_TMP/go" "$TEST_TMP/done"
exec 3<>"$TEST_TMP/go" 4<>"$TEST_TMP/done"
cat > "$TEST_TMP/loop.sh" <<LOOP
while IFS= read -r _ < "$TEST_TMP/go"; do
  bash "$ROOT_DIR/hooks/codex.sh" < "$TEST_TMP/payload"
  echo > "$TEST_TMP/done"
done
LOOP
tmux_t new-session -d -x 80 -y 24 "sh $TEST_TMP/loop.sh"
pane="$(tmux_t display-message -p '#{pane_id}')"

# Events of session s1 unless $2 names another.
run_hook() {
  printf '{"hook_event_name":"%s","session_id":"%s"%s}' "$1" "${2:-s1}" "${3:-}" \
    > "$TEST_TMP/payload"
  echo >&3
  IFS= read -r -t 5 _ <&4 || fail "the hook did not run in the pane"
}
option() { tmux_t show-options -pv -t "$pane" "$1" 2>/dev/null; }

# A turn with an approved command
run_hook SessionStart
assert_eq "idle" "$(option @agent_state)" "session start"
assert_eq "codex" "$(option @agent_app)" "app"
assert_eq "s1" "$(option @agent_session)" "session recorded"
run_hook UserPromptSubmit
assert_eq "running" "$(option @agent_state)" "prompt"
run_hook PermissionRequest
assert_eq "needs-input" "$(option @agent_state)" "permission request"
run_hook PostToolUse
assert_eq "running" "$(option @agent_state)" "approved tool ran"
run_hook Stop
assert_eq "done" "$(option @agent_state)" "turn ended"
assert_eq "" "$(option @agent_transcript)" "no transcript recorded"

# A denied command: Interrupt ends the turn
run_hook UserPromptSubmit
run_hook PermissionRequest
run_hook Interrupt
assert_eq "idle" "$(option @agent_state)" "denied"

# A subagent; Esc while it runs ends everything
run_hook UserPromptSubmit
run_hook SubagentStart s1 ',"agent_id":"a1"'
assert_eq "subagent-running" "$(option @agent_state)" "subagent started"
run_hook PostToolUse s1 ',"agent_id":"a1"'
assert_eq "subagent-running" "$(option @agent_state)" "subagent tool"
run_hook SubagentStop s1 ',"agent_id":"a1"'
assert_eq "running" "$(option @agent_state)" "subagent finished"
run_hook SubagentStart s1 ',"agent_id":"a2"'
run_hook Interrupt
assert_eq "idle" "$(option @agent_state)" "interrupted"
assert_eq "0" "$(option @agent_subagents)" "interrupt drains the count"

# Codex reports a session's end up to a minute late. By then another
# session may be running in the pane: its badge stays.
run_hook UserPromptSubmit s2
assert_eq "s2" "$(option @agent_session)" "the new session takes the pane"
run_hook SessionEnd s1
assert_eq "running" "$(option @agent_state)" "a late end for another session is ignored"
assert_eq "codex" "$(option @agent_app)" "the badge stays"

# The end of the session on the pane removes the badge and every option.
run_hook SessionEnd s2
for opt in @agent_state @agent_app @agent_session @agent_subagents @agent_updated @agent_schema; do
  assert_eq "" "$(option "$opt")" "$opt unset on exit"
done

# Codex's shared background server runs every session's hooks with the
# environment of the pane that first started it, so TMUX_PANE can name any
# pane. Such a hook's parent has no terminal: it writes nothing.
printf '{"hook_event_name":"UserPromptSubmit","session_id":"s3"}' |
  TMUX_PANE="$pane" python3 -c '
import os, subprocess, sys
os.setsid()
subprocess.run(sys.argv[1:])' bash "$ROOT_DIR/hooks/codex.sh"
assert_eq "" "$(option @agent_state)" "a hook run by the background server writes nothing"
