#!/usr/bin/env bash
# Infer agent-bar styles from the user's existing status line and apply
# them: the last fg=/bg= style block before #I in window-status-format
# (inactive) and window-status-current-format (active), and the accent
# from status-left's first background. Prints the `set -g` lines to add
# to tmux.conf, applies them to the running server, and reapplies the bar.
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

infer() { # $1: format string, $2: mode (block|accent)
  python3 - "$1" "$2" <<'PY'
import re
import sys

fmt, mode = sys.argv[1], sys.argv[2]
if mode == "block":
    fmt = fmt.split("#I")[0]
blocks = re.findall(r"#\[([^\]]*)\]", fmt)
for block in (blocks if mode == "accent" else reversed(blocks)):
    tokens = re.split(r"[,\s]+", block)
    fg = next((t for t in tokens if t.startswith("fg=")), None)
    bg = next((t for t in tokens if t.startswith("bg=")), None)
    if mode == "accent" and bg:
        print(bg[3:])
        break
    if mode == "block" and fg and bg:
        print(f"{fg} {bg}")
        break
PY
}

window="$(infer "$(tmux show -gv window-status-format 2>/dev/null || true)" block)"
active="$(infer "$(tmux show -gv window-status-current-format 2>/dev/null || true)" block)"
accent="$(infer "$(tmux show -gv status-left 2>/dev/null || true)" accent)"
status_bg="$(tmux show -gv status-style 2>/dev/null | tr ', ' '\n\n' | sed -n 's/^bg=//p' | head -1)"
[ -n "$status_bg" ] || status_bg="$(tmux show -gv status-bg 2>/dev/null || true)"

[ -n "$window" ] || { echo "could not infer a style from window-status-format" >&2; exit 1; }
[ -n "$active" ] || { echo "could not infer a style from window-status-current-format" >&2; exit 1; }

tmux set -g @agent_bar_style_window "$window"
tmux set -g @agent_bar_style_window_active "$active"
[ -n "$accent" ] && tmux set -g @agent_bar_accent "$accent"
[ -n "$status_bg" ] && tmux set -g @agent_bar_status_bg "$status_bg"

bash "$ROOT_DIR/agent-bar.tmux"

printf 'Applied. Add to tmux.conf (before the agent-bar run-shell):\n'
printf '  set -g @agent_bar_style_window "%s"\n' "$window"
printf '  set -g @agent_bar_style_window_active "%s"\n' "$active"
[ -n "$accent" ] && printf '  set -g @agent_bar_accent "%s"\n' "$accent"
[ -n "$status_bg" ] && printf '  set -g @agent_bar_status_bg "%s"\n' "$status_bg"
