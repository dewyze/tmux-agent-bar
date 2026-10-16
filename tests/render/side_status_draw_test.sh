#!/usr/bin/env bash
# The vertical bar actually draws: the plugin runs against an inner tmux with
# @agent_bar_position left, an outer tmux gives the inner client a terminal,
# and capturing the outer pane shows the side status line tmux rendered.
# Skips (exit 101) when the tmux on PATH has no side-status.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

OUTER="agent-bar-side-outer-$$"
INNER="agent-bar-side-inner-$$"
REAL_TMUX="$(command -v tmux)"
tmux_o() { "$REAL_TMUX" -L "$OUTER" -f /dev/null "$@"; }
tmux_i() { "$REAL_TMUX" -L "$INNER" -f /dev/null "$@"; }
trap 'tmux_o kill-server 2>/dev/null; tmux_i kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT
unset TMUX

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$INNER" -f /dev/null "\$@"
SHIM
chmod +x "$TEST_TMP/bin/tmux"

tmux_i new-session -d -s work -n api -x 80 -y 24 \; \
  new-window -d -n web \; \
  new-session -d -s blog -n docs
if ! tmux_i set-option -g side-status off 2>/dev/null; then
  echo "$("$REAL_TMUX" -V) has no side-status"
  exit 101
fi
pane="$(tmux_i list-panes -t work:api -F '#{pane_id}')"
tmux_i set-option -p -t "$pane" @agent_state running \; \
  set-option -p -t "$pane" @agent_app claude \; \
  set-option -g @agent_bar_position left
PATH="$TEST_TMP/bin:$PATH" bash "$ROOT_DIR/agent-bar.tmux"

tmux_o new-session -d -x 80 -y 12 "$REAL_TMUX -L '$INNER' -f /dev/null attach -t work"

wait_for() {
  local needle="$1"
  captured=""
  for _ in $(seq 1 24); do
    captured="$(tmux_o capture-pane -p)"
    case "$captured" in *"$needle"*) return ;; esac
    sleep 0.5
  done
}

# Row N of the capture starts with the given text (a byte match, so the
# box-drawing edge compares the same in any locale)
assert_row() {
  local n="$1" prefix="$2" label="$3" row
  row="$(sed -n "${n}p" <<<"$captured")"
  case "$row" in
    "$prefix"*) ;;
    *) fail "assert_row ($label): row $n [$row] does not start with [$prefix]" ;;
  esac
}

# Tree rows down the left edge: the local session's windows, the agent
# badge under its window, then the foreign session's header and windows.
# The edge line sits in column 25: @agent_bar_width 24, plus one.
wait_for "* claude"
assert_row 1 "api                     │" "window row"
assert_row 2 "  * claude              │" "badge row"
assert_row 3 "web                     │" "agent-less window row"
assert_row 4 " ▌ blog                 │" "foreign session header row"
assert_row 5 "  docs                  │" "foreign window row"

# A state change redraws the bar without any explicit refresh
tmux_i set-option -p -t "$pane" @agent_state needs-input
wait_for "? claude"
assert_row 2 "  ? claude              │" "redraw on state change"

# Overflow: more rows than the bar's 11 keeps the current window visible,
# with markers on the first and last rows for the rows hidden above and below
for i in $(seq 2 20); do tmux_i new-window -d -t work -n "w$i"; done
tmux_i select-window -t work:w12
wait_for "↑"
grep -q '^w12 ' <<<"$captured" || fail "current window row not visible: $captured"
assert_row 1 "↑" "more-above marker"
assert_row 11 "↓" "more-below marker"

# The focus is the viewing session's current window, never a foreign
# session's: after switching to a session listed below work's rows, work's
# current window (w12) gives way to it
tmux_i new-session -d -s zed -n zz
tmux_i switch-client -c "$(tmux_i list-clients -F '#{client_name}')" -t zed
wait_for " ▌ work"
grep -q '^zz ' <<<"$captured" || fail "viewing session's window not visible: $captured"
