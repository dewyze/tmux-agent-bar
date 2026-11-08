#!/usr/bin/env bash
# A turn that ends in a pane someone is already looking at leaves no "+": the
# hook writes idle instead of done. "Looking at" is the plugin's
# acknowledgement test: the active pane of a window a client is viewing.
# Real server, a control-mode client attached so "viewing" means on a client.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-watched-$$"
REAL_TMUX="$(command -v tmux)"
tmux_t() { "$REAL_TMUX" -L "$SOCKET" -f /dev/null "$@"; }
cleanup() {
  exec 9>&- 2>/dev/null
  tmux_t kill-server 2>/dev/null
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" -f /dev/null "\$@"
SHIM
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"
unset TMUX

tmux_t new-session -d -s work -n api -x 80 -y 24
tmux_t split-window -d -t work:api
tmux_t new-window -d -t work -n db
tmux_t new-session -d -s side -x 80 -y 24
viewed="$(tmux_t list-panes -t work:api -F '#{pane_id}' | sed -n '1p')"
beside="$(tmux_t list-panes -t work:api -F '#{pane_id}' | sed -n '2p')"
background="$(tmux_t display-message -p -t work:db '#{pane_id}')"
unviewed="$(tmux_t display-message -p -t side '#{pane_id}')"

# Keep a control-mode client attached to `work` on fd 9
exec 9> >("$REAL_TMUX" -L "$SOCKET" -f /dev/null -C attach -t work >/dev/null 2>&1)
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -n "$(tmux_t list-clients -F '#{client_session}' 2>/dev/null)" ] && break
  sleep 0.2
done
assert_eq "work" "$(tmux_t list-clients -F '#{client_session}')" "client starts on work"
assert_eq "$viewed" "$(tmux_t display-message -p -t work '#{pane_id}')" "client is on the viewed pane"

stop() {
  printf '%s' '{"hook_event_name":"Stop"}' | TMUX_PANE="$1" bash "$ROOT_DIR/hooks/claude.sh"
}
state() { tmux_t show-options -pv -t "$1" @agent_state 2>/dev/null; }

stop "$viewed"
assert_eq "idle" "$(state "$viewed")" "pane in view finishes idle"

stop "$beside"
assert_eq "done" "$(state "$beside")" "inactive pane of the viewed window keeps done"

stop "$background"
assert_eq "done" "$(state "$background")" "background window keeps done"

stop "$unviewed"
assert_eq "done" "$(state "$unviewed")" "session no client is viewing keeps done"
