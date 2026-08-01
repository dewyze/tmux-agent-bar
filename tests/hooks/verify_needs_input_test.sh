#!/usr/bin/env bash
# scripts/verify-needs-input.sh: user denials emit NO hook event, so a
# needs-input badge can go stale. The agent's transcript is the truth: any
# entry newer than the badge (@agent_updated) means the prompt was answered.
# No transcript evidence -> badge stays (fail-safe, and non-Claude agents
# writing the schema are never wrongly cleared).
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-verify-$$"
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

tmux_t new-session -d -s work -x 80 -y 24
tmux_t split-window -d -t work
pane="$(tmux_t list-panes -t work -F '#{pane_id}' | sed -n '1p')"
other="$(tmux_t list-panes -t work -F '#{pane_id}' | sed -n '2p')"

state() { tmux_t show-options -pv -t "$1" @agent_state 2>/dev/null; }
verify() { bash "$ROOT_DIR/scripts/verify-needs-input.sh"; }

# Fixture transcripts: JSONL entries with ISO timestamps relative to NOW
NOW="$(date +%s)"
iso() { python3 -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'))" "$1"; }
transcript() { # $1=file, entries from remaining "type:epoch" args
  local file="$1"; shift
  : > "$file"
  local entry
  for entry in "$@"; do
    printf '{"type":"%s","uuid":"x","timestamp":"%s"}\n' \
      "${entry%%:*}" "$(iso "${entry#*:}")" >> "$file"
  done
}

set_badge() { # pane transcript_file
  tmux_t set-option -p -t "$1" @agent_state needs-input \; \
    set-option -p -t "$1" @agent_updated "$NOW" \; \
    set-option -p -t "$1" @agent_transcript "${2:-}"
}

# Transcript untouched since the badge -> still waiting, badge stays
transcript "$TEST_TMP/waiting.jsonl" "assistant:$((NOW - 30))"
set_badge "$pane" "$TEST_TMP/waiting.jsonl"
verify
assert_eq "needs-input" "$(state "$pane")" "older transcript keeps badge"

# Transcript progressed after the badge -> prompt was answered, badge clears
transcript "$TEST_TMP/answered.jsonl" "assistant:$((NOW - 30))" "user:$((NOW + 30))"
set_badge "$pane" "$TEST_TMP/answered.jsonl"
verify
assert_eq "idle" "$(state "$pane")" "newer transcript clears badge"

# Fail-safe: no positive evidence -> badge stays
set_badge "$pane" ""
verify
assert_eq "needs-input" "$(state "$pane")" "no transcript recorded keeps badge"

set_badge "$pane" "$TEST_TMP/missing.jsonl"
verify
assert_eq "needs-input" "$(state "$pane")" "missing transcript file keeps badge"

printf 'not json\n' > "$TEST_TMP/garbage.jsonl"
set_badge "$pane" "$TEST_TMP/garbage.jsonl"
verify
assert_eq "needs-input" "$(state "$pane")" "malformed transcript keeps badge"

# A trailing malformed line must not hide real progress above it
transcript "$TEST_TMP/trailing.jsonl" "user:$((NOW + 30))"
printf '{"partial\n' >> "$TEST_TMP/trailing.jsonl"
set_badge "$pane" "$TEST_TMP/trailing.jsonl"
verify
assert_eq "idle" "$(state "$pane")" "partial trailing line still detects progress"

# Panes in other states are never touched
tmux_t set-option -p -t "$other" @agent_state running
verify
assert_eq "running" "$(state "$other")" "running pane untouched"
