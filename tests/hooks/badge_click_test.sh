#!/usr/bin/env bash
# Clicking the bar moves the client: a badge to its pane (session, window,
# pane), a window label to that window (its own active pane), a session name
# to that session. Real clicks: an inner tmux runs the plugin with the mouse
# on, its client runs in an outer tmux pane, and SGR mouse sequences typed
# into that pane arrive as the inner client's terminal input.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

OUTER="agent-bar-click-outer-$$"
INNER="agent-bar-click-inner-$$"
REAL_TMUX="$(command -v tmux)"
tmux_o() { "$REAL_TMUX" -L "$OUTER" -f /dev/null "$@"; }
tmux_i() { "$REAL_TMUX" -L "$INNER" -f /dev/null "$@"; }
trap 'tmux_o kill-server 2>/dev/null; tmux_i kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT
unset TMUX
export SHELL=/bin/sh

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$INNER" -f /dev/null "\$@"
SHIM
chmod +x "$TEST_TMP/bin/tmux"

tmux_i new-session -d -s work -n api -x 90 -y 24
# The status-line bar: the default is the side bar.
tmux_i set-option -g @agent_bar_position status
tmux_i new-session -d -s home -n notes -x 90 -y 24
tmux_i split-window -d -t home:notes
tmux_i new-window -d -t home -n misc
agent="$(tmux_i list-panes -t home:notes -F '#{pane_id}' | sed -n '2p')"
other="$(tmux_i list-panes -t home:notes -F '#{pane_id}' | sed -n '1p')"
tmux_i set-option -p -t "$agent" @agent_state needs-input
tmux_i set-option -g mouse on
PATH="$TEST_TMP/bin:$PATH" bash "$ROOT_DIR/agent-bar.tmux"

# The outer pane is the inner client's terminal; its last row is the bar.
tmux_o new-session -d -x 90 -y 24 "$REAL_TMUX -L $INNER -f /dev/null attach -t work"
tmux_o set-option -g status off

bar() { tmux_o capture-pane -p | tail -1; }
client() { tmux_i list-clients -F "$1"; }

# Waits up to 3s for the client to show $1 for format $2.
wait_client() {
  local _
  for _ in $(seq 1 30); do
    [ "$(client "$2")" = "$1" ] && return 0
    sleep 0.1
  done
}

# Puts the client back on `work` with home's current window `misc`, and waits
# until the bar shows home's badge.
reset_view() {
  tmux_i select-window -t home:misc
  tmux_i switch-client -t work
  wait_client work '#{client_session}'
  local _
  for _ in $(seq 1 30); do
    case "$(bar)" in *"home ║ notes │ ?"*) return 0 ;; esac
    sleep 0.1
  done
  fail "bar never showed home's badge: [$(bar)]"
}

# Presses and releases mouse button $1 (0 left, 2 right) on the first $2
# on the bar. tmux reads a press within 300ms of the last one as a second
# click, which is not a MouseDown, so each click waits that out first.
click() {
  local line col
  sleep 0.35
  line="$(bar)"
  col="$(python3 -c 'import sys; print(sys.argv[1].find(sys.argv[2]) + 1)' "$line" "$2")"
  [ "$col" -gt 0 ] || fail "[$2] not on the bar: [$line]"
  tmux_o send-keys -l $'\e[<'"$1;$col;24M"$'\e[<'"$1;$col;24m"
}

# The inner client attaches in the background: wait for it, or the first
# switch-client finds no client.
wait_client work '#{client_session}'
[ "$(client '#{client_session}')" = work ] || fail "the inner client never attached"

# Badge: the agent's session, window and pane
reset_view
click 0 "?"
wait_client home '#{client_session}'
assert_eq "home" "$(client '#{client_session}')" "badge click switches session"
assert_eq "notes" "$(client '#{window_name}')" "badge click selects the window"
assert_eq "$agent" "$(client '#{pane_id}')" "badge click selects the pane"

# Window label: that window, keeping its own active pane
tmux_i select-pane -t "$other"
reset_view
click 0 "notes"
wait_client home '#{client_session}'
assert_eq "notes" "$(client '#{window_name}')" "label click selects the window"
assert_eq "$other" "$(client '#{pane_id}')" "label click keeps the window's pane"

# Session name: that session's current window
reset_view
click 0 "home"
wait_client home '#{client_session}'
assert_eq "misc" "$(client '#{window_name}')" "session click keeps its window"

# Right-click menu, Jump (j): same as a badge click
reset_view
click 2 "?"
sleep 0.3
tmux_o send-keys j
wait_client home '#{client_session}'
assert_eq "home" "$(client '#{client_session}')" "menu jump switches session"
assert_eq "$agent" "$(client '#{pane_id}')" "menu jump selects the pane"
