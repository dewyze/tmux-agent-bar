#!/usr/bin/env bash
# resolve_agent_state: the harness-agnostic state machine, pure function of
# (state, subagent_event, count) -> "state count" or "skip". Every harness
# writer shares this; parsers only vary.
. "$(dirname "$0")/../testlib.sh"
. "$ROOT_DIR/lib/hook-lib.sh"

check() {
  local expected="$1" state="$2" event="$3" count="$4"
  assert_eq "$expected" "$(resolve_agent_state "$state" "$event" "$count")" \
    "state=$state event=$event count=$count"
}

# Subagent start: increment, force subagent-running
check "subagent-running 1" running start 0
check "subagent-running 3" running start 2

# Subagent stop: decrement; subagent-running while any remain
check "subagent-running 1" running stop 2
check "running 0" running stop 1
# Stale stop (count 0, e.g. background agent finishing after Stop): no write
check "skip" running stop 0

# Soft running (tool activity): respects subagent bookkeeping, never resets
check "subagent-running 2" running soft 2
check "running 0" running soft 0

# Terminal events drain the refcount (lost SubagentStop can't stick)
check "running 0" running "" 3
check "done 0" done "" 3
check "idle 0" idle "" 3

# Attention states preserve the count
check "needs-input 2" needs-input "" 2
check "error 2" error "" 2
