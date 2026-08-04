#!/usr/bin/env bash
# agent-bar.tmux (plugin entry): enables line 1, installs the bar format and
# the two mouse bindings. tmux is stubbed; assert the issued commands.
. "$(dirname "$0")/../testlib.sh"

STUB_LOG="$TEST_TMP/tmux.log"
STATUS_FILE="$TEST_TMP/status_value"
POSITION_FILE="$TEST_TMP/position_value"
SIDE_FAIL="$TEST_TMP/side_fail"
mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STUB_LOG"
if [ "\$1" = "show-options" ]; then
  case "\$*" in
    *" status") cat "$STATUS_FILE" 2>/dev/null ;;
    *@agent_bar_position*) cat "$POSITION_FILE" 2>/dev/null ;;
  esac
fi
if [ "\$1" = "set-option" ] && [ -f "$SIDE_FAIL" ]; then
  case "\$*" in
    *" side-status "*|*" side-status") exit 1 ;;
  esac
fi
STUB
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"

run_plugin() {
  rm -f "$STUB_LOG"
  printf '%s' "$1" > "$STATUS_FILE"
  bash "$ROOT_DIR/agent-bar.tmux"
}

# Default single status line -> raised to 2, format installed, bindings bound
run_plugin "on"
log="$(cat "$STUB_LOG")"
assert_contains "$log" "set-option -g status 2" "status raised to 2"
assert_contains "$log" "set-option -gu side-status" "status mode undoes side claims"
assert_contains "$log" "set-option -g status-format[1] #{S:" "bar format installed"
# Mouse bindings are generated as a tmux conf fragment (native {} quoting)
# and sourced; non-badge clicks must fall through to replayed tmux defaults.
assert_contains "$log" "source-file" "bindings fragment sourced"
bindings="$ROOT_DIR/.bindings.generated.conf"
[ -f "$bindings" ] || fail "bindings fragment not generated"
b="$(cat "$bindings")"
assert_contains "$b" "MouseDown1Status" "left-click bound"
assert_contains "$b" "MouseDown3Status" "right-click bound"
assert_contains "$b" "mouse_status_line" "guard on status line"
assert_contains "$b" "jump.sh" "left-click jumps"
assert_contains "$b" "[%@\$][0-9]" "left-click guard accepts pane/window/session ids"
assert_contains "$b" "switch-client -t=" "left-click default replayed"
assert_contains "$b" "display-menu" "right-click opens menu directly"
assert_contains "$b" "-x M -y S" "agent menu at mouse x, above the bar"
assert_contains "$b" "display-menu -O" "menu stays open on quick click (-O)"
assert_not_contains "$b" "-T 'Agent #{mouse_status_range}'" "title is not the pane id"
assert_contains "$b" "#{==:#{pane_id},#{mouse_status_range}}" "title resolves clicked pane"
assert_contains "$b" "#{?#{@agent_name},#{@agent_name},#{@agent_app}}" "title uses name chain"
assert_contains "$b" "kill-pane -t '#{mouse_status_range}'" "kill targets clicked pane"
assert_contains "$b" "confirm-before" "kill is confirmed"
assert_contains "$b" "@agent_state idle" "clear item present"
assert_contains "$b" "command-prompt" "rename item prompts"
assert_contains "$b" "@agent_name" "rename sets agent name"
assert_contains "$b" "swap-window -t:-1" "default window menu replayed"
assert_contains "$b" "New At End" "default window menu complete"

# status off is treated the same as on: the bar needs two lines
run_plugin "off"
assert_contains "$(cat "$STUB_LOG")" "set-option -g status 2" "status off raised"

# A user already running >2 lines keeps their setting
run_plugin "3"
assert_not_contains "$(cat "$STUB_LOG")" "set-option -g status 2" "status 3 preserved"
assert_contains "$(cat "$STUB_LOG")" "set-option -g status-format[1]" "format still installed"

# Side mode (feature supported): claims side-status options, does NOT touch
# the status line count, undoes status-mode format claims; the mouse guard
# drops the line check (side-bar clicks carry no status line)
printf 'left' > "$POSITION_FILE"
run_plugin "on"
log="$(cat "$STUB_LOG")"
assert_contains "$log" "set-option -g side-status left" "side-status set"
assert_contains "$log" "set-option -g side-status-width" "width set"
assert_contains "$log" "set-option -g side-status-format[0] #{S:" "side format installed"
assert_contains "$log" "set-option -gu status-format[1]" "side mode undoes status format"
assert_not_contains "$log" "set-option -g status 2" "side mode leaves status count alone"
b="$(cat "$ROOT_DIR/.bindings.generated.conf")"
assert_not_contains "$b" "mouse_status_line" "side-mode guard is pattern-only"
assert_contains "$b" "jump.sh" "side-mode bindings present"

# Stock tmux (probe fails): falls back to the status-line bar
touch "$SIDE_FAIL"
run_plugin "on"
log="$(cat "$STUB_LOG")"
assert_contains "$log" "set-option -g status 2" "fallback raises status"
assert_contains "$log" "set-option -g status-format[1] #{S:" "fallback installs status format"
rm -f "$SIDE_FAIL" "$POSITION_FILE"
