#!/usr/bin/env bash
# agent-bar.tmux (plugin entry): enables line 1, installs the bar format and
# the two mouse bindings. tmux is stubbed; assert the issued commands.
. "$(dirname "$0")/../testlib.sh"

STUB_LOG="$TEST_TMP/tmux.log"
STATUS_FILE="$TEST_TMP/status_value"
mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STUB_LOG"
if [ "\$1" = "show-options" ]; then
  case "\$*" in
    *" status") cat "$STATUS_FILE" 2>/dev/null ;;
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
assert_contains "$log" "set-option -g status-format[1] #{S:#{W:" "bar format installed"
assert_contains "$log" "bind-key -n MouseDown1Status" "left-click bound"
assert_contains "$log" "bind-key -n MouseDown3Status" "right-click bound"
assert_contains "$log" "mouse_status_line" "bindings guard on status line"
assert_contains "$log" "mouse_status_range" "bindings read clicked range"
assert_contains "$log" "jump.sh" "left-click jumps"

# The menu opens directly in the binding so it keeps the live mouse event:
# -x M -y M positions at the click, and tmux's native menu handles both
# hold-release and click-to-stay. A run-shell detour loses both.
assert_contains "$log" "display-menu" "right-click opens menu directly"
assert_contains "$log" "-x M -y M" "menu positioned at mouse"
assert_not_contains "$log" "menu.sh" "no run-shell detour for the menu"
assert_contains "$log" "kill-pane -t '#{mouse_status_range}'" "kill targets clicked pane"
assert_contains "$log" "confirm-before" "kill is confirmed"
assert_contains "$log" "@agent_state idle" "clear item present"

# status off is treated the same as on: the bar needs two lines
run_plugin "off"
assert_contains "$(cat "$STUB_LOG")" "set-option -g status 2" "status off raised"

# A user already running >2 lines keeps their setting
run_plugin "3"
assert_not_contains "$(cat "$STUB_LOG")" "set-option -g status 2" "status 3 preserved"
assert_contains "$(cat "$STUB_LOG")" "set-option -g status-format[1]" "format still installed"
