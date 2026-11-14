#!/usr/bin/env bash
# The side bar drawn as blocks, from options: a pointed end on filled names
# (@agent_bar_theme nerdfont), session names as filled blocks
# (@agent_bar_style_session), and a guide line down a session's rows
# (@agent_bar_guide). All off by default.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-blocks-$$"
tmux_t() { command tmux -L "$SOCKET" -f /dev/null "$@"; }
cleanup() { exec 9>&- 2>/dev/null; tmux_t kill-server 2>/dev/null; rm -rf "$TEST_TMP"; }
trap cleanup EXIT
unset TMUX

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
exec "$(command -v tmux)" -L "$SOCKET" -f /dev/null "\$@"
SHIM
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"

tmux_t new-session -d -s work -n api -x 80 -y 24
tmux_t new-session -d -s blog -n web -x 80 -y 24
local_pane="$(tmux_t list-panes -t work:api -F '#{pane_id}')"
foreign_pane="$(tmux_t list-panes -t blog:web -F '#{pane_id}')"
tmux_t set-option -p -t "$local_pane" @agent_state running \; \
  set-option -p -t "$local_pane" @agent_app claude
tmux_t set-option -p -t "$foreign_pane" @agent_state needs-input \; \
  set-option -p -t "$foreign_pane" @agent_app claude

exec 9> >(command tmux -L "$SOCKET" -f /dev/null -C attach -t work >/dev/null 2>&1)
client=""
for _ in $(seq 1 10); do
  client="$(tmux_t list-clients -F '#{client_name}' 2>/dev/null | head -1)"
  [ -n "$client" ] && break
  sleep 0.2
done
[ -n "$client" ] || fail "control client never attached"

raw() { tmux_t display-message -p -c "$client" "$(bash "$ROOT_DIR/lib/bar-format.sh")"; }
plain() { raw | sed 's/#\[nl\]/|/g; s/#\[[^]]*\]//g'; }
api_id="$(tmux_t display-message -p -t work:api '#{window_id}')"
web_id="$(tmux_t display-message -p -t blog:web '#{window_id}')"
work_id="$(tmux_t display-message -p -t work '#{session_id}')"
blog_id="$(tmux_t display-message -p -t blog '#{session_id}')"
tip="$(printf '\xee\x82\xb0')"
[ -n "$tip" ] || fail "powerline glyph construction failed"

# By default: no pointed ends, no guide, session names as marked text
assert_not_contains "$(raw)" "$tip" "no pointed ends by default"
assert_not_contains "$(raw)" "│" "no guide by default"
assert_contains "$(plain)" "▌ work" "session mark by default"

# nerdfont: the current window, when its style has a fill, ends in a point
# of that colour. Another session's current window does not.
tmux_t set-option -g @agent_bar_theme nerdfont
tmux_t set-option -g @agent_bar_session_marker " > "
tmux_t set-option -g @agent_bar_style_window_active "fg=colour254 bg=colour239"
assert_contains "$(raw)" "#[range=user|$api_id] api #[norange]#[default]#[fg=colour239]$tip" "current window ends in a point"
assert_eq "1" "$(raw | grep -o "$tip" | grep -c .)" "only the viewer's current window"
tmux_t set-option -g @agent_bar_style_window_active "fg=colour250 bold"
assert_not_contains "$(raw)" "$tip" "no fill, no point"
tmux_t set-option -gu @agent_bar_theme

# @agent_bar_style_session with a fill: session names are padded blocks,
# the viewer's in bold, and the mark goes
tmux_t set-option -g @agent_bar_style_session "fg=colour235 bg=colour109"
assert_contains "$(raw)" "#[fg=colour235 bg=colour109 bold]#[range=user|$work_id] work #[norange]" "viewer's session is a bold block"
assert_contains "$(raw)" "#[fg=colour235 bg=colour109]#[range=user|$blog_id] blog #[norange]" "another session is a block"
assert_not_contains "$(plain)" ">" "no session mark on a block"
tmux_t set-option -g @agent_bar_padding 0
assert_contains "$(raw)" "#[range=user|$blog_id]blog#[norange]" "blocks follow the padding option"
tmux_t set-option -gu @agent_bar_padding
assert_not_contains "$(raw)" "$tip" "blocks have no point without nerdfont"
tmux_t set-option -g @agent_bar_theme nerdfont
assert_contains "$(raw)" "#[range=user|$blog_id] blog #[norange]#[default]#[fg=colour109]$tip" "nerdfont: session block ends in a point"
tmux_t set-option -gu @agent_bar_theme

# ... without a fill it only styles the name, and the mark stays
tmux_t set-option -g @agent_bar_style_session "fg=colour9"
assert_contains "$(raw)" "#[fg=colour9]#[range=user|$blog_id]blog#[norange]" "styled name"
assert_contains "$(plain)" "> blog" "mark kept"
tmux_t set-option -gu @agent_bar_style_session
tmux_t set-option -gu @agent_bar_session_marker
tmux_t set-option -gu @agent_bar_style_window_active

# @agent_bar_guide: a dim line down the left of the rows under a session
tmux_t set-option -g @agent_bar_guide "│"
assert_contains "$(raw)" "#[nl] #[fg=colour240]│#[default]" "guide in the divider colour"
assert_contains "$(plain)" "| │ api " "guide before a window"
assert_contains "$(plain)" "| │  * claude" "guide before a badge"
# One session on the bar: no header, so nothing to hang a guide on
tmux_t set-option -pu -t "$foreign_pane" @agent_state
assert_not_contains "$(raw)" "│" "flat rows have no guide"
