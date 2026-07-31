# Shared helpers for agent hook wrappers. Source, don't execute.

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
