#!/usr/bin/env bash
# Vertical layout (@agent_bar_position left/right): same badges, rows joined
# by #[nl] — window label row, indented pane rows, session header rows for
# foreign sessions. No horizontal separators, no powerline segments.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-vert-$$"
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

tmux_t set-option -g @agent_bar_position left
fmt="$(bash "$ROOT_DIR/lib/bar-format.sh")"

# Rows join with #[nl]; horizontal separators are absent
assert_contains "$fmt" "#[nl]" "rows joined by nl"
assert_not_contains "$fmt" "║" "no horizontal group separator"
assert_not_contains "$fmt" "│" "no horizontal pane separator"

exec 9> >(command tmux -L "$SOCKET" -f /dev/null -C attach -t work >/dev/null 2>&1)
client=""
for _ in $(seq 1 10); do
  client="$(tmux_t list-clients -F '#{client_name}' 2>/dev/null | head -1)"
  [ -n "$client" ] && break
  sleep 0.2
done
[ -n "$client" ] || fail "control client never attached"
out="$(tmux_t display-message -p -c "$client" "$fmt")"
shown="$(printf '%s' "$out" | sed 's/#\[[^]]*\]//g')"

# Local window: label row, then indented badge row; foreign session gets a
# header row. Badges keep ranges (clickable), labels keep theirs.
assert_contains "$shown" "api" "window label row"
assert_contains "$shown" "* claude" "badge row content"
assert_contains "$shown" "blog" "foreign session header"
assert_contains "$out" "#[range=user|$local_pane]" "pane range kept"
assert_contains "$out" "#[range=user|$foreign_pane]" "foreign pane range kept"
win_id="$(tmux_t display-message -p -t work:api '#{window_id}')"
assert_contains "$out" "#[range=user|$win_id]" "window label range kept"

# Hierarchy indent: local windows flat with 2-space pane rows; foreign
# windows (under their session header) indent 2, their panes 4
assert_contains "$out" "#[nl]  #[range=user|$local_pane]" "local pane 2-space indent"
case "$out" in
  *"#[nl]  #["*) ;;
  *) fail "foreign window row not indented: $out" ;;
esac
assert_contains "$out" "#[nl]    #[range=user|$foreign_pane]" "foreign pane 4-space indent"

# The tree is always present: windows without agents still get label rows
# (the bar is a navigation surface with zero agents), but only agent panes
# get badge rows
tmux_t new-window -t work -n extra
extra_pane="$(tmux_t list-panes -t work:extra -F '#{pane_id}')"
tree_fmt="$(bash "$ROOT_DIR/lib/bar-format.sh")"
tree_out="$(tmux_t display-message -p -c "$client" "$tree_fmt")"
tree_shown="$(printf '%s' "$tree_out" | sed 's/#\[[^]]*\]//g')"
assert_contains "$tree_shown" "extra" "agent-less window still gets a row"
assert_not_contains "$tree_out" "#[range=user|$extra_pane]" "agent-less pane gets no badge row"

# Zero agents anywhere: the full tree still renders
tmux_t set-option -pu -t "$foreign_pane" @agent_state
empty_out="$(tmux_t display-message -p -c "$client" "$(bash "$ROOT_DIR/lib/bar-format.sh")" | sed 's/#\[[^]]*\]//g')"
assert_contains "$empty_out" "blog" "agent-less session header still renders"
assert_contains "$empty_out" "web" "agent-less foreign window still renders"
tmux_t set-option -p -t "$foreign_pane" @agent_state needs-input
tmux_t kill-window -t work:extra

# cross_session off still filters foreign in vertical
tmux_t set-option -g @agent_bar_cross_session off
off_fmt="$(bash "$ROOT_DIR/lib/bar-format.sh")"
off_shown="$(tmux_t display-message -p -c "$client" "$off_fmt" | sed 's/#\[[^]]*\]//g')"
assert_not_contains "$off_shown" "blog" "off hides foreign vertically"
tmux_t set-option -gu @agent_bar_cross_session
tmux_t set-option -gu @agent_bar_position
