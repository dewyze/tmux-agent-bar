#!/usr/bin/env bash
# @agent_bar_* options: every knob overrides its themed default. Options are
# read when bar-format.sh builds the format, so each case rebuilds it.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-opts-$$"
tmux_t() { command tmux -L "$SOCKET" -f /dev/null "$@"; }
trap 'tmux_t kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT
unset TMUX

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
exec "$(command -v tmux)" -L "$SOCKET" -f /dev/null "\$@"
SHIM
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"

tmux_t new-session -d -s work -n api -x 80 -y 24
pane="$(tmux_t list-panes -t work:api -F '#{pane_id}')"
tmux_t set-option -p -t "$pane" @agent_state running
tmux_t select-pane -T "fixing the tests" -t "$pane"

shown() { tmux_t display-message -p "$(bash "$ROOT_DIR/lib/bar-format.sh")" | sed 's/#\[[^]]*\]//g'; }

# Glyph override
tmux_t set-option -g @agent_bar_glyph_running "R"
assert_contains "$(shown)" "│ R" "glyph override"
tmux_t set-option -gu @agent_bar_glyph_running

# Badge text truncation via name_max
tmux_t set-option -p -t "$pane" @agent_name "reviewer"
tmux_t set-option -g @agent_bar_name_max 3
assert_contains "$(shown)" "* rev" "name truncated to name_max"
assert_not_contains "$(shown)" "reviewer" "long name cut"
tmux_t set-option -gu @agent_bar_name_max
tmux_t set-option -pu -t "$pane" @agent_name

# Label suffix restores the colon grammar
tmux_t set-option -g @agent_bar_label_suffix ":"
assert_contains "$(shown)" "work/api:" "label suffix"
tmux_t set-option -gu @agent_bar_label_suffix

# Pane separator override
tmux_t set-option -g @agent_bar_pane_separator " >> "
assert_contains "$(shown)" "work/api >> *" "pane separator override"
tmux_t set-option -gu @agent_bar_pane_separator

# Nerdfont theme swaps in powerline dividers. The glyphs are PUA chars
# that tooling can silently drop, so build them from bytes and refuse a
# vacuous empty pattern (this exact test once passed asserting "").
powerline_thin="$(printf '\xee\x82\xb1')"
[ -n "$powerline_thin" ] || fail "powerline glyph construction failed"
tmux_t set-option -g @agent_bar_theme nerdfont
assert_contains "$(shown)" "$powerline_thin" "nerdfont thin divider"
assert_not_contains "$(shown)" "│" "ascii divider replaced"
tmux_t set-option -gu @agent_bar_theme

# Session separator override
tmux_t set-option -g @agent_bar_session_separator "."
assert_contains "$(shown)" "work.api" "session separator override"
tmux_t set-option -gu @agent_bar_session_separator
