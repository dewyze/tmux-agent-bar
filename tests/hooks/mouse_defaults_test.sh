#!/usr/bin/env bash
# Non-badge status clicks must keep working: our mouse bindings carry
# else-arms replaying tmux's defaults (switch-client on left-click, the
# window menu on right-click). Verified against a real server's key table.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-mouse-$$"
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

tmux_t new-session -d -x 80 -y 24
bash "$ROOT_DIR/agent-bar.tmux"

left="$(tmux_t list-keys -T root | grep "MouseDown1Status")"
assert_contains "$left" "jump.sh" "badge click present"
assert_contains "$left" "switch-client -t =" "default fall-through present"

right="$(tmux_t list-keys -T root | grep "MouseDown3Status")"
assert_contains "$right" "Agent" "agent menu present"
assert_contains "$right" "swap-window" "default window menu present"
assert_contains "$right" "kill-window" "default menu complete"

# @agent_bar_mouse off: mouse keys are left entirely untouched
SOCKET2="agent-bar-mouse2-$$"
tmux_2() { "$REAL_TMUX" -L "$SOCKET2" -f /dev/null "$@"; }
trap 'tmux_t kill-server 2>/dev/null; tmux_2 kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET2" -f /dev/null "\$@"
SHIM
tmux_2 new-session -d -x 80 -y 24
tmux_2 set-option -g @agent_bar_mouse off
bash "$ROOT_DIR/agent-bar.tmux"
off_left="$(tmux_2 list-keys -T root | grep "MouseDown1Status")"
assert_not_contains "$off_left" "jump.sh" "mouse off leaves left-click alone"
assert_contains "$off_left" "switch-client -t =" "stock default untouched"
