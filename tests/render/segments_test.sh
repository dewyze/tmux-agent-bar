#!/usr/bin/env bash
# Powerline segment mode: nerdfont theme + window styles with backgrounds +
# a known status background render groups as true segments — transition
# chevrons colored old-bg-over-new-bg at both edges, conditional on
# window_active, and thin dividers take a contrasting fg.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-seg-$$"
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
tmux_t set-option -g @agent_bar_theme nerdfont
tmux_t set-option -g @agent_bar_status_bg colour236
tmux_t set-option -g @agent_bar_style_window "fg=colour254 bg=colour236"
tmux_t set-option -g @agent_bar_style_window_active "fg=colour254 bg=colour239"

fmt="$(bash "$ROOT_DIR/lib/bar-format.sh")"

# Transition chevrons: in = status-bg over group-bg, out = group-bg over
# status-bg, active variant selected by window_active
assert_contains "$fmt" "#[fg=colour236 bg=colour239]" "active in-transition colors"
assert_contains "$fmt" "#[fg=colour239 bg=colour236]" "active out-transition colors"
assert_contains "$fmt" "window_active" "transitions conditional on active window"

# Thin dividers get the contrasting segment-mode default, not colour240
assert_contains "$fmt" "#[fg=colour245]" "divider contrast fg in segment mode"

# The dim flat group opener is replaced by transitions in segment mode
assert_not_contains "$fmt" "#[fg=colour240] " "no flat dim opener in segment mode"

# Divider fg is an option
tmux_t set-option -g @agent_bar_divider_fg colour111
assert_contains "$(bash "$ROOT_DIR/lib/bar-format.sh")" "#[fg=colour111]" "divider fg option"
tmux_t set-option -gu @agent_bar_divider_fg

# Without a status_bg, segment mode stays off (flat separators as before)
tmux_t set-option -gu @agent_bar_status_bg
assert_contains "$(bash "$ROOT_DIR/lib/bar-format.sh")" "#[fg=colour240]" "flat mode without status_bg"
