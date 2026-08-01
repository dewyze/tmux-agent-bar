# Shared helpers for agent hook wrappers. Source, don't execute.

# The harness-agnostic state machine (SCHEMA.md): pure function of
# (state, subagent_event, count) -> "state count" on stdout, or "skip" when
# nothing must be written. Harness writers share this; only parsers vary.
#
#   start  -> increment refcount, force subagent-running
#   stop   -> decrement; subagent-running while any remain; a stop at count
#             0 is stale (e.g. a background agent finishing after Stop
#             already wrote done) and must not write
#   soft   -> activity: respects the refcount, never resets it
#   (none) -> terminal states (running/done/idle) drain the refcount so a
#             lost stop can't pin subagent-running; attention states
#             (needs-input/error) preserve it
resolve_agent_state() {
  local state="$1" subagent_event="$2" count="$3"
  case "$subagent_event" in
    start)
      count=$((count + 1))
      state="subagent-running"
      ;;
    stop)
      if [ "$count" -le 0 ]; then
        printf 'skip\n'
        return 0
      fi
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
      case "$state" in
        running|done|idle) count=0 ;;
      esac
      ;;
  esac
  printf '%s %s\n' "$state" "$count"
}

# Read stdin only if data is ready within 50ms, so a hook invoked without a
# payload never hangs waiting on a pipe that stays open.
read_ready_stdin() {
  python3 -c '
import select, sys
if select.select([sys.stdin], [], [], 0.05)[0]:
    sys.stdout.write(sys.stdin.read())
'
}

# Populate HOOK_PAYLOAD and HOOK_EVENT_ARG from argv/stdin. Accepts either
# "event-name" + JSON on stdin, or JSON as an argument (either order).
resolve_hook_input() {
  HOOK_PAYLOAD=""
  HOOK_EVENT_ARG=""
  local arg
  for arg in "$@"; do
    case "$arg" in
      \{*|\[*) HOOK_PAYLOAD="$arg" ;;
      ?*) HOOK_EVENT_ARG="$arg" ;;
    esac
  done
  if [ -z "$HOOK_PAYLOAD" ]; then
    HOOK_PAYLOAD="$(read_ready_stdin)"
  fi
}
