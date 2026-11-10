#!/usr/bin/env bash
# Clicking the vertical bar moves the client, as clicking the status-line bar
# does (badge_click_test.sh): a badge to its pane, a window row to that
# window, a session header to that session. Real clicks: SGR mouse sequences
# typed into the outer pane that is the inner client's terminal.
# Skips (exit 101) when the tmux on PATH has no side-status.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

OUTER="agent-bar-sclick-outer-$$"
INNER="agent-bar-sclick-inner-$$"
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
if ! tmux_i set-option -g side-status off 2>/dev/null; then
  echo "$("$REAL_TMUX" -V) has no side-status"
  exit 101
fi
tmux_i new-session -d -s home -n notes -x 90 -y 24
tmux_i split-window -d -t home:notes
tmux_i new-window -d -t home -n misc
agent="$(tmux_i list-panes -t home:notes -F '#{pane_id}' | sed -n '2p')"
other="$(tmux_i list-panes -t home:notes -F '#{pane_id}' | sed -n '1p')"
tmux_i set-option -p -t "$agent" @agent_state needs-input
tmux_i set-option -g mouse on
tmux_i set-option -g @agent_bar_position left
PATH="$TEST_TMP/bin:$PATH" bash "$ROOT_DIR/agent-bar.tmux"

tmux_o new-session -d -x 90 -y 24 "$REAL_TMUX -L $INNER -f /dev/null attach -t work"
tmux_o set-option -g status off

# The bar: the first 24 columns of each row of the inner client's screen.
bar() { tmux_o capture-pane -p | cut -c1-24; }
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
    case "$(bar)" in *"▌ home"*"notes"*"?"*) return 0 ;; esac
    sleep 0.1
  done
  fail "bar never showed home's badge: [$(bar)]"
}

# Presses and releases mouse button $1 (0 left, 2 right) on the first $2 on
# the bar. tmux reads a press within 300ms of
# the last one as a second click, which is not a MouseDown, so each click
# waits that out first.
click() {
  local pos
  sleep 0.35
  pos="$(bar | python3 -c '
import sys
for row, line in enumerate(sys.stdin.read().split("\n")):
    col = line.find(sys.argv[1])
    if col >= 0:
        print("%d;%d" % (col + 1, row + 1))
        break' "$2")"
  [ -n "$pos" ] || fail "[$2] not on the bar: [$(bar)]"
  tmux_o send-keys -l $'\e[<'"$1;${pos}M"$'\e[<'"$1;${pos}m"
}

# Badge: the agent's session, window and pane
reset_view
click 0 "?"
wait_client home '#{client_session}'
assert_eq "home" "$(client '#{client_session}')" "badge click switches session"
assert_eq "notes" "$(client '#{window_name}')" "badge click selects the window"
assert_eq "$agent" "$(client '#{pane_id}')" "badge click selects the pane"

# Window row: that window, keeping its own active pane
tmux_i select-pane -t "$other"
reset_view
click 0 "notes"
wait_client home '#{client_session}'
assert_eq "notes" "$(client '#{window_name}')" "window click selects the window"
assert_eq "$other" "$(client '#{pane_id}')" "window click keeps the window's pane"

# Session header: that session's current window
reset_view
click 0 "home"
wait_client home '#{client_session}'
assert_eq "home" "$(client '#{client_session}')" "session click switches session"
assert_eq "misc" "$(client '#{window_name}')" "session click keeps its window"

# Right-click menu, Jump (j): same as a badge click
reset_view
click 2 "?"
sleep 0.3
tmux_o send-keys j
wait_client home '#{client_session}'
assert_eq "home" "$(client '#{client_session}')" "menu jump switches session"
assert_eq "$agent" "$(client '#{pane_id}')" "menu jump selects the pane"
