#!/usr/bin/env bash
# scripts/adopt-theme.sh: infer bar styles from the user's existing status
# line — the last fg=/bg= style block before #I in each window format, and
# the accent from status-left's first background.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-theme-$$"
REAL_TMUX="$(command -v tmux)"
tmux_t() { "$REAL_TMUX" -L "$SOCKET" -f /dev/null "$@"; }
trap 'tmux_t kill-server 2>/dev/null; rm -rf "$TEST_TMP"' EXIT

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/tmux" <<SHIM
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" -f /dev/null "\$@"
SHIM
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"
unset TMUX

tmux_t new-session -d -x 80 -y 24
tmux_t setw -g window-status-format "#[fg=colour254,bg=colour236] #I #[fg=colour254,bg=colour236] #W "
tmux_t setw -g window-status-current-format "#[fg=colour236,bg=colour239,nobold]#[fg=colour255,bg=colour239] #I #W #[fg=colour239,bg=colour236,nobold]"
tmux_t set -g status-left "#[fg=colour235,bg=colour109,bold] #S #[fg=colour109,bg=colour236]"

out="$(bash "$ROOT_DIR/scripts/adopt-theme.sh")"

assert_eq "fg=colour254 bg=colour236" "$(tmux_t show -gv @agent_bar_style_window)" "inactive inferred"
assert_eq "fg=colour255 bg=colour239" "$(tmux_t show -gv @agent_bar_style_window_active)" "active inferred (last block before #I)"
assert_eq "colour109" "$(tmux_t show -gv @agent_bar_accent)" "accent from status-left bg"
assert_contains "$out" 'set -g @agent_bar_style_window' "prints conf lines"
