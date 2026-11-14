#!/usr/bin/env bash
# scripts/adopt-theme.sh on the side bar: the bar takes the status line's
# colours (tmux's side-status-style), window names and session names take
# the ones inferred from the status line's formats.
# Skips (exit 101) when the tmux on PATH has no side-status.
. "$(dirname "$0")/../testlib.sh"

command -v tmux >/dev/null 2>&1 || fail "tmux not installed"

SOCKET="agent-bar-theme-side-$$"
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
if ! tmux_t show-options -gv side-status >/dev/null 2>&1; then
  echo "$("$REAL_TMUX" -V) has no side-status"
  exit 101
fi
tmux_t set -g status-style "bg=colour236,fg=colour254"

# A status line with nothing to infer from: the bar's colours still follow
out="$(bash "$ROOT_DIR/scripts/adopt-theme.sh")"
assert_eq "bg=colour236,fg=colour254" "$(tmux_t show -gv side-status-style)" "bar takes the status line's colours"
assert_eq "" "$(tmux_t show -gqv @agent_bar_style_window)" "no window style to infer"
assert_contains "$out" 'set -g side-status-style "bg=colour236,fg=colour254"' "prints the conf line"

# A styled status line: window and session names follow too
tmux_t setw -g window-status-format "#[fg=colour254,bg=colour236] #I #[fg=colour254,bg=colour236] #W "
tmux_t setw -g window-status-current-format "#[fg=colour236,bg=colour239,nobold]#[fg=colour255,bg=colour239] #I #W #[fg=colour239,bg=colour236,nobold]"
tmux_t set -g status-left "#[fg=colour235,bg=colour109,bold] #S #[fg=colour109,bg=colour236]"
out="$(bash "$ROOT_DIR/scripts/adopt-theme.sh")"
assert_eq "fg=colour254 bg=colour236" "$(tmux_t show -gv @agent_bar_style_window)" "inactive inferred"
assert_eq "fg=colour255 bg=colour239" "$(tmux_t show -gv @agent_bar_style_window_active)" "active inferred"
assert_eq "colour109" "$(tmux_t show -gv @agent_bar_accent)" "accent from status-left bg"
assert_eq "fg=colour235 bg=colour109 bold" "$(tmux_t show -gv @agent_bar_style_session)" "session block from status-left's first block"
assert_contains "$out" 'set -g @agent_bar_style_session "fg=colour235 bg=colour109 bold"' "prints the session line"
assert_eq "" "$(tmux_t show -gqv @agent_bar_status_bg)" "status bg is a status-line option"
assert_contains "$out" 'set -g @agent_bar_style_window_active' "prints the window lines"
assert_eq "left" "$(tmux_t show -gv side-status)" "the side bar is still up"

# A status line whose colours live in its window formats, with a
# status-style that names no background: the bar takes the inactive
# window's colours.
for style in none "fg=white,bg=default"; do
  tmux_t set -g status-style "$style"
  tmux_t set -gu side-status-style
  out="$(bash "$ROOT_DIR/scripts/adopt-theme.sh")"
  assert_eq "fg=colour254,bg=colour236" "$(tmux_t show -gv side-status-style)" "status-style $style: bar takes the window colours"
  assert_contains "$out" 'set -g side-status-style "fg=colour254,bg=colour236"' "status-style $style: prints the conf line"
done

# Nothing to match anywhere: the bar's colours are left alone, and the
# script says so.
tmux_t setw -gu window-status-format
tmux_t setw -gu window-status-current-format
tmux_t set -gu status-left
tmux_t set -g status-style none
tmux_t set -g side-status-style "bg=colour52"
if bash "$ROOT_DIR/scripts/adopt-theme.sh" >/dev/null 2>"$TEST_TMP/err"; then
  fail "nothing to match should be an error"
fi
assert_file_contains "$TEST_TMP/err" "found nothing to match" "says why"
assert_eq "bg=colour52" "$(tmux_t show -gv side-status-style)" "bar colours left alone"

# A status-left block with a fill but no text colour is an accent, not a
# session block
tmux_t set -gu @agent_bar_style_session
tmux_t set -g status-left "#[bg=colour109] #S "
bash "$ROOT_DIR/scripts/adopt-theme.sh" >/dev/null
assert_eq "colour109" "$(tmux_t show -gv @agent_bar_accent)" "accent still inferred"
assert_eq "" "$(tmux_t show -gqv @agent_bar_style_session)" "no session block without a text colour"

# A colour that is a tmux conditional cannot be copied: the script skips
# what it cannot read and still applies the rest
tmux_t set -gu @agent_bar_accent
tmux_t set -gu @agent_bar_style_session
tmux_t set -g status-style "bg=colour236,fg=colour254"
tmux_t set -g status-left "#[fg=colour235,bg=#{?client_prefix,#f0c674,colour109},bold] #S #[fg=#{?client_prefix,#f0c674,colour109},bg=colour236]"
out="$(bash "$ROOT_DIR/scripts/adopt-theme.sh")"
assert_eq "" "$(tmux_t show -gqv @agent_bar_accent)" "no accent from a conditional colour"
assert_eq "" "$(tmux_t show -gqv @agent_bar_style_session)" "no session block from a conditional colour"
assert_not_contains "$out" "#{" "nothing conditional in the printed lines"
assert_eq "bg=colour236,fg=colour254" "$(tmux_t show -gv side-status-style)" "the rest is still applied"

# The same in a window format: no window style is taken from it
tmux_t set -gu @agent_bar_style_window
tmux_t setw -g window-status-format "#[fg=#{?window_bell_flag,red,colour254},bg=colour236] #I #W "
bash "$ROOT_DIR/scripts/adopt-theme.sh" >/dev/null
assert_eq "" "$(tmux_t show -gqv @agent_bar_style_window)" "no window style from a conditional colour"
