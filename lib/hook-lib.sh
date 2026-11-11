# Shared helpers for agent hook wrappers. Source, don't execute.

# The harness-agnostic state machine (SCHEMA.md): pure function of
# (state, subagent_event, count) -> "state count" on stdout, or "skip" when
# nothing must be written. The state may be a tmux format, evaluated as it
# is written; a count of "-" leaves the stored count alone. Harness writers
# share this; only parsers vary.
#
#   start  -> increment refcount, force subagent-running
#   stop   -> decrement; subagent-running while any remain; a stop at count
#             0 is stale (e.g. a background agent finishing after Stop
#             already wrote done) and must not write
#   soft   -> activity: subagent-running while any remain. tmux reads the
#             count as it writes and the count is left alone: hooks run
#             concurrently, and a start or stop landing between this
#             hook's read and write must not be undone
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
      state="#{?#{e|>:#{@agent_subagents},0},subagent-running,$state}"
      count=-
      ;;
    *)
      case "$state" in
        running|done|idle) count=0 ;;
      esac
      ;;
  esac
  printf '%s %s\n' "$state" "$count"
}

# The generic harness writer: everything after parsing is identical for
# every agent. A new harness integration is exactly two files:
#   lib/parse-<app>.py  — pure: payload on stdin (+ optional event
#                         argv) -> 4-line protocol on stdout:
#                         state, subagent event (start/stop/soft),
#                         transcript, who the event is from (an agent id,
#                         "main", or blank; the line is optional)
#   hooks/<app>.sh      — four lines: source this file, run_agent_hook <app>
# Schema stamping, the subagent state machine, exit-unsets, tracing, and
# batched writes all come from here (see SCHEMA.md for the contract).
# Always exits 0 so a failure never disturbs the harness.
run_agent_hook() {
  local app="$1"
  shift
  # This runs on every event, so it sticks to bash builtins: each helper
  # program it forks (dirname, sed, date, cat) costs about 3ms. Keep it
  # bash 3.2 compatible too, for macOS's /bin/bash. The wrapper sources
  # this file by path, so BASH_SOURCE always has a directory part.
  local lib_dir="${BASH_SOURCE[0]%/*}"
  local root_dir="$lib_dir/.."

  resolve_hook_input "$@"

  local result state subagent_event transcript asker
  # On stdin, not in the environment: exec caps an environment variable
  # (1MB on macOS, 128KB on Linux) and a big payload would be dropped.
  result="$(python3 "$lib_dir/parse-$app.py" "$HOOK_EVENT_ARG" <<<"$HOOK_PAYLOAD")" || return 0
  { IFS= read -r state; IFS= read -r subagent_event; IFS= read -r transcript; IFS= read -r asker; } <<<"$result"
  # The asker goes into a tmux format below: anything but a plain id is
  # dropped, which falls back to not telling agents apart.
  [[ "$asker" =~ ^[A-Za-z0-9_-]+$ ]] || asker=""

  # Opt-in diagnostics: `tmux set -g @agent_bar_trace /path/to/log` records
  # every event (including no-ops) with its parse result.
  local trace_file
  trace_file="$(tmux show-options -gv @agent_bar_trace 2>/dev/null || true)"
  if [ -n "$trace_file" ]; then
    printf '%s pane=%s state=%s sub=%s payload=%s\n' \
      "$(date '+%Y-%m-%dT%H:%M:%S')" "${TMUX_PANE:-none}" "$state" \
      "$subagent_event" "$HOOK_PAYLOAD" >> "$trace_file" 2>/dev/null || true
  fi

  [ -n "$state" ] || return 0

  local pane="${TMUX_PANE:-}"
  [[ "$pane" =~ ^%[0-9]+$ ]] || return 0

  if [ "$state" = "exit" ]; then
    tmux set-option -pu -t "$pane" @agent_app \; \
      set-option -pu -t "$pane" @agent_state \; \
      set-option -pu -t "$pane" @agent_subagents \; \
      set-option -pu -t "$pane" @agent_updated \; \
      set-option -pu -t "$pane" @agent_transcript \; \
      set-option -pu -t "$pane" @agent_asker \; \
      set-option -pu -t "$pane" @agent_writer_version \; \
      set-option -pu -t "$pane" @agent_schema 2>/dev/null
    return 0
  fi

  local count resolved
  count="$(tmux show-options -pv -t "$pane" @agent_subagents 2>/dev/null || true)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0

  resolved="$(resolve_agent_state "$state" "$subagent_event" "$count")"
  [ "$resolved" = "skip" ] && return 0
  state="${resolved% *}"
  count="${resolved##* }"

  # A turn that ends in a pane someone is looking at has been seen: done
  # would leave a "+" they must navigate away and back to clear. tmux checks
  # as it writes, with the plugin's acknowledgement test (agent-bar.tmux):
  # the active pane of a window a client is viewing.
  if [ "$state" = "done" ]; then
    state='#{?#{&&:#{pane_active},#{window_active_clients}},idle,done}'
  fi

  # A "?" belongs to the agent that asked (@agent_asker): the main agent or
  # one subagent. Tool and subagent events from anyone else leave it up;
  # tmux compares as it writes. A "?" with no asker recorded clears on any
  # activity. A needs-input event that does not say who asked (a
  # notification) keeps the asker of a "?" already up.
  local asker_write=""
  if [ "$state" = "needs-input" ]; then
    asker_write="$asker"
    if [ -z "$asker" ]; then
      asker_write='#{?#{==:#{@agent_state},needs-input},#{@agent_asker},main}'
    fi
  elif [ -n "$subagent_event" ] && [ -n "$asker" ]; then
    state="#{?#{&&:#{==:#{@agent_state},needs-input},#{&&:#{@agent_asker},#{!=:#{@agent_asker},$asker}}},needs-input,$state}"
  fi

  # The state is written with -F: a plain state word expands to itself.
  # EPOCHSECONDS is bash 5+; bash 3.2 falls back to date.
  local version=unknown write
  read -r version 2>/dev/null <"$root_dir/VERSION"
  write=(set-option -p -t "$pane" @agent_app "$app")
  if [ -n "$asker_write" ]; then
    # Before the state: the format reads the state being replaced.
    write+=(\; set-option -pF -t "$pane" @agent_asker "$asker_write")
  fi
  write+=(\; set-option -pF -t "$pane" @agent_state "$state"
    \; set-option -p -t "$pane" @agent_updated "${EPOCHSECONDS:-$(date +%s)}"
    \; set-option -p -t "$pane" @agent_writer_version "$version"
    \; set-option -p -t "$pane" @agent_schema 1)
  if [ "$count" != "-" ]; then
    write+=(\; set-option -p -t "$pane" @agent_subagents "$count")
  fi
  if [ -n "$transcript" ]; then
    write+=(\; set-option -p -t "$pane" @agent_transcript "$transcript")
  fi
  tmux "${write[@]}" 2>/dev/null

  return 0
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
  # Wait up to a second for the payload to start, so a hook invoked without
  # one never hangs on a pipe that stays open. Whole seconds: macOS's bash
  # 3.2 rejects a fractional timeout. cat, not $(</dev/stdin): Linux can't
  # open /dev/stdin when stdin is a socket.
  local first
  if [ -z "$HOOK_PAYLOAD" ] && IFS= read -r -t 1 -n 1 first; then
    HOOK_PAYLOAD="$first$(cat)"
  fi
}
