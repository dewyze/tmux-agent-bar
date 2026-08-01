#!/usr/bin/env bash
# scripts/reset.sh: return a server to a clean state matching this checkout —
# every @agent_* pane option cleared, bar and bindings reapplied.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-reset-$$"
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
pane_a="$(tmux_t list-panes -t work -F '#{pane_id}' | sed -n '1p')"
pane_b="$(tmux_t list-panes -t work -F '#{pane_id}' | sed -n '2p')"

tmux_t set-option -p -t "$pane_a" @agent_state needs-input \; \
  set-option -p -t "$pane_a" @agent_app claude \; \
  set-option -p -t "$pane_a" @agent_transcript /tmp/x.jsonl \; \
  set-option -p -t "$pane_a" @agent_writer_version 0.0.1 \; \
  set-option -p -t "$pane_a" @agent_name reviewer
tmux_t set-option -p -t "$pane_b" @agent_state running

bash "$ROOT_DIR/scripts/reset.sh" >/dev/null

for opt in @agent_state @agent_app @agent_transcript @agent_writer_version @agent_schema @agent_name; do
  assert_eq "" "$(tmux_t show-options -pv -t "$pane_a" "$opt" 2>/dev/null)" "$opt cleared on pane_a"
done
assert_eq "" "$(tmux_t show-options -pv -t "$pane_b" @agent_state 2>/dev/null)" "@agent_state cleared on pane_b"

assert_eq "2" "$(tmux_t show-options -gv status)" "bar reapplied"
[ "$(tmux_t list-keys | grep -c agent-bar)" -ge 2 ] || fail "bindings reapplied"
