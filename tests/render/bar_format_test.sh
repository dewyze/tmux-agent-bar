#!/usr/bin/env bash
# lib/bar-format.sh prints the status-format[1] string; expanding it against a
# real server must render one clickable badge per non-idle agent pane.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-render-$$"
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
tmux_t new-session -d -s home -n notes -x 80 -y 24
tmux_t split-window -d -t work:api

agent_pane="$(tmux_t list-panes -t work:api -F '#{pane_id}' | head -1)"
plain_pane="$(tmux_t list-panes -t work:api -F '#{pane_id}' | sed -n '2p')"
home_pane="$(tmux_t list-panes -t home:notes -F '#{pane_id}')"

format="$(bash "$ROOT_DIR/lib/bar-format.sh")"
render() { tmux_t display-message -p "$format"; }
# Visible text only — what format_draw would paint; use for label/glyph
# assertions. Range assertions read the raw expansion via render().
shown() { render | sed 's/#\[[^]]*\]//g'; }

# No agent state anywhere -> empty bar
assert_eq "" "$(render | tr -d ' ')" "empty bar without agents"

# One running agent renders a clickable badge with session:window label
tmux_t set-option -p -t "$agent_pane" @agent_state running
out="$(render)"
assert_contains "$out" "#[range=user|$agent_pane]" "range opens with pane id"
assert_contains "$out" "#[norange]" "range closes"
assert_contains "$out" "work/api" "session-prefixed label"
assert_not_contains "$out" "home:notes" "stateless pane renders nothing"

# States get distinct glyphs; the window label leads its group
tmux_t set-option -p -t "$agent_pane" @agent_state needs-input
assert_contains "$(shown)" "work/api │ ?" "needs-input glyph"
tmux_t set-option -p -t "$agent_pane" @agent_state done
assert_contains "$(shown)" "work/api │ +" "done glyph"
tmux_t set-option -p -t "$agent_pane" @agent_state error
assert_contains "$(shown)" "work/api │ !" "error glyph"
tmux_t set-option -p -t "$agent_pane" @agent_state subagent-running
assert_contains "$(shown)" "work/api │ **" "subagent glyph"

# idle is a live agent waiting for input: dim badge, still clickable —
# only an unset state (agent gone) renders nothing
tmux_t set-option -p -t "$agent_pane" @agent_state idle
assert_contains "$(shown)" "work/api │ ·" "idle renders dim badge"
assert_contains "$(render)" "#[range=user|$agent_pane]" "idle badge clickable"
tmux_t set-option -pu -t "$agent_pane" @agent_state
assert_eq "" "$(render | tr -d ' ')" "unset state renders nothing"

# Two agents in different sessions both render, independently clickable,
# each group bracketed so window groups are visually delimited
tmux_t set-option -p -t "$agent_pane" @agent_state running
tmux_t set-option -p -t "$home_pane" @agent_state needs-input
out="$(render)"
assert_contains "$out" "#[range=user|$agent_pane]" "first badge range"
assert_contains "$out" "#[range=user|$home_pane]" "second badge range"
assert_contains "$(shown)" "║ work/api │ *" "first group opened by group bar"
assert_contains "$(shown)" "║ home/notes │ ?" "second group opened by group bar"
assert_eq "2" "$(shown | grep -o '║' | grep -c .)" "one group bar per group, none dangling"

# Agents in the same window group under ONE label: win label once, one
# glyph range per pane (also covers non-active panes via the P loop)
tmux_t set-option -p -t "$plain_pane" @agent_state running
tmux_t select-pane -t "$agent_pane"
out="$(render)"
assert_contains "$out" "#[range=user|$plain_pane]" "non-active pane badge"
assert_eq "1" "$(printf '%s' "$out" | grep -o 'work/api' | grep -c .)" "window label appears once"

# Badge text precedence: our name -> harness name -> nothing. Pane
# titles and commands never render.
tmux_t set-option -pu -t "$plain_pane" @agent_state
tmux_t set-option -p -t "$agent_pane" @agent_state running
tmux_t select-pane -T "fixing the tests" -t "$agent_pane"
assert_not_contains "$(shown)" "fixing the tests" "pane title never renders"
assert_not_contains "$(render)" "$(hostname)" "hostname never renders"

tmux_t set-option -p -t "$agent_pane" @agent_app claude
assert_contains "$(shown)" "work/api │ * claude" "harness name is the default"
tmux_t set-option -p -t "$agent_pane" @agent_name "reviewer"
assert_contains "$(shown)" "* reviewer" "our name beats harness name"
assert_not_contains "$(shown)" "claude" "rename replaces harness name"
tmux_t set-option -pu -t "$agent_pane" @agent_name
assert_contains "$(shown)" "* claude" "falls back to harness name"
tmux_t set-option -pu -t "$agent_pane" @agent_app

# Session prefix only when foreign: with no client every session is foreign
# (asserted above via work:api); with a client attached to work, work drops
# the prefix and home keeps it.
exec 9> >(command tmux -L "$SOCKET" -f /dev/null -C attach -t work >/dev/null 2>&1)
client=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  client="$(tmux_t list-clients -F '#{client_name}' 2>/dev/null | head -1)"
  [ -n "$client" ] && break
  sleep 0.2
done
[ -n "$client" ] || fail "control client never attached"
attached="$(tmux_t display-message -p -c "$client" "$format" | sed 's/#\[[^]]*\]//g')"
exec 9>&-
assert_contains "$attached" "api │ *" "local badge keeps window name"
assert_not_contains "$attached" "work/api" "local session prefix hidden"
assert_contains "$attached" "home/notes │ ?" "foreign session prefix kept"
