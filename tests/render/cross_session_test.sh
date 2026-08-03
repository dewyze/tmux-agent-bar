#!/usr/bin/env bash
# Cross-session rendering modes (@agent_bar_cross_session):
#   inline (default) — one line: local windows bare, foreign sessions
#                      introduced by an accent marker + session name once
#   line             — primary line local-only; foreign sessions compact
#                      (marker + name + bare glyphs) via `bar-format.sh foreign`
#   off              — local only, foreign invisible
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-xs-$$"
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

# Attach a control client to `work` so local/foreign is real
exec 9> >(command tmux -L "$SOCKET" -f /dev/null -C attach -t work >/dev/null 2>&1)
client=""
for _ in $(seq 1 10); do
  client="$(tmux_t list-clients -F '#{client_name}' 2>/dev/null | head -1)"
  [ -n "$client" ] && break
  sleep 0.2
done
[ -n "$client" ] || fail "control client never attached"

shown() { # $1: bar-format.sh argument
  tmux_t display-message -p -c "$client" "$(bash "$ROOT_DIR/lib/bar-format.sh" "${1:-}")" |
    sed 's/#\[[^]]*\]//g'
}

# inline (default): both sessions on one line; foreign gets marker + name
out="$(shown)"
assert_contains "$out" "api │ * claude" "local window bare"
assert_contains "$out" "▌ blog" "foreign session marker + name"
assert_contains "$out" "web │ ? claude" "foreign window bare label"
assert_not_contains "$out" "blog/web" "no per-window session prefixes"
assert_not_contains "$out" "▌ work" "local session never marked"

# line mode: primary line is local-only
tmux_t set-option -g @agent_bar_cross_session line
assert_contains "$(shown)" "api │ * claude" "line mode keeps local"
assert_not_contains "$(shown)" "blog" "line mode hides foreign from primary"

# ...and the foreign line is compact: marker + name + glyph, no window
# labels, no agent names, still clickable
fout="$(shown foreign)"
assert_contains "$fout" "▌ blog" "foreign line session intro"
assert_contains "$fout" "?" "foreign line glyph"
assert_not_contains "$fout" "web" "foreign line has no window labels"
assert_not_contains "$fout" "claude" "foreign line has no agent names"
raw="$(tmux_t display-message -p -c "$client" "$(bash "$ROOT_DIR/lib/bar-format.sh" foreign)")"
assert_contains "$raw" "#[range=user|$foreign_pane]" "foreign glyph clickable"
assert_not_contains "$(shown foreign)" "api" "foreign line excludes local"

# off: foreign invisible everywhere
tmux_t set-option -g @agent_bar_cross_session off
assert_not_contains "$(shown)" "blog" "off hides foreign"
assert_contains "$(shown)" "api │ * claude" "off keeps local"
tmux_t set-option -gu @agent_bar_cross_session
