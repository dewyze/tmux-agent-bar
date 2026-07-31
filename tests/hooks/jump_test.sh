#!/usr/bin/env bash
# scripts/jump.sh <pane_id>: moves the client to the pane's session, window,
# and pane. A control-mode client is attached so switch-client has a target.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-jump-$$"
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
tmux_t new-window -t work -n db
tmux_t new-session -d -s home -n notes -x 80 -y 24
tmux_t split-window -d -t home:notes
target="$(tmux_t list-panes -t home:notes -F '#{pane_id}' | sed -n '2p')"

# Keep a control-mode client attached to `work` on fd 9
exec 9> >("$REAL_TMUX" -L "$SOCKET" -f /dev/null -C attach -t work >/dev/null 2>&1)
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -n "$(tmux_t list-clients -F '#{client_session}' 2>/dev/null)" ] && break
  sleep 0.2
done
assert_eq "work" "$(tmux_t list-clients -F '#{client_session}')" "client starts on work"

bash "$ROOT_DIR/scripts/jump.sh" "$target"

assert_eq "home" "$(tmux_t list-clients -F '#{client_session}')" "client switched session"
assert_eq "$(tmux_t display-message -p -t "$target" '#{window_id}')" \
  "$(tmux_t display-message -p -t home: '#{window_id}')" "session current window"
assert_eq "$target" "$(tmux_t list-panes -t home:notes -F '#{pane_id}#{?pane_active,*,}' | grep '\*$' | tr -d '*')" "pane active"

# Garbage input is rejected without touching tmux
before="$(tmux_t list-clients -F '#{client_session}')"
bash "$ROOT_DIR/scripts/jump.sh" "not-a-pane" && fail "jump.sh should exit non-zero on bad input"
assert_eq "$before" "$(tmux_t list-clients -F '#{client_session}')" "no switch on bad input"
