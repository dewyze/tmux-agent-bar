#!/usr/bin/env bash
# scripts/menu.sh <pane_id> <mouse_x> <mouse_y>: issues one display-menu with
# the pane id baked into every item command. tmux is stubbed; assert argv.
. "$(dirname "$0")/../testlib.sh"

STUB_LOG="$TEST_TMP/tmux.log"
mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STUB_LOG"
STUB
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"

bash "$ROOT_DIR/scripts/menu.sh" "%12" "40" "23"
log="$(cat "$STUB_LOG")"

assert_contains "$log" "display-menu" "issues display-menu"
assert_contains "$log" "-x 40 -y 23" "positioned at click"
assert_contains "$log" "jump.sh %12" "jump item targets pane"
assert_contains "$log" "-t %12 @agent_state idle" "clear item targets pane"
assert_contains "$log" "kill-pane -t %12" "kill item targets pane"
assert_contains "$log" "confirm-before" "kill is confirmed"
assert_eq "1" "$(grep -c . "$STUB_LOG")" "single tmux invocation"

# Bad pane id -> no menu
rm -f "$STUB_LOG"
bash "$ROOT_DIR/scripts/menu.sh" "; kill-server" "1" "1" && fail "menu.sh should reject bad pane id"
[ ! -f "$STUB_LOG" ] || fail "menu.sh touched tmux with bad input: $(cat "$STUB_LOG")"
