#!/usr/bin/env bash
# Make the agent bar match the user's existing status line. Applies to the
# running server, reapplies the bar, and prints the `set -g` lines to add
# to tmux.conf.
#
# Inferred from the status line: the last fg=/bg= style block before #I in
# window-status-format (inactive) and window-status-current-format
# (active), and the accent from status-left's first background.
#
# Side bar: the bar itself (tmux's side-status-style, which the plugin
# never sets on its own) takes status-style, or the inactive window's
# colours when status-style names no background; window and session names
# take whatever could be inferred.
# Status-line bar: the inferred styles and the status background; nothing
# to infer is an error.
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

# The side bar, when it is asked for and this tmux has one.
. "$ROOT_DIR/lib/options.sh"
side=0
if [ "$(bar_option position left)" != "status" ] && tmux show -gv side-status >/dev/null 2>&1; then
  side=1
fi

lines=()
apply() { # $1: option, $2: value
  tmux set -g "$1" "$2"
  lines+=("set -g $1 \"$2\"")
}

if [ "$side" = 1 ]; then
  # The bar's own colours: status-style when it names a background. A
  # status line can leave that bare and colour itself in its window
  # formats, so next the inactive window's colours, then whatever colour
  # status-style does have.
  status_style="$(tmux show -gv status-style 2>/dev/null || true)"
  bar_style=""
  case ",${status_style// /,}," in
    *,bg=default,*) ;;
    *,bg=*) bar_style="$status_style" ;;
  esac
  if [ -z "$bar_style" ] && [ -n "$window" ]; then
    bar_style="${window// /,}"
  fi
  if [ -z "$bar_style" ]; then
    case "$status_style" in *fg=*|*bg=*) bar_style="$status_style" ;; esac
  fi
  [ -n "$bar_style" ] && apply side-status-style "$bar_style"
  [ -n "$window" ] && apply @agent_bar_style_window "$window"
  [ -n "$active" ] && apply @agent_bar_style_window_active "$active"
else
  [ -n "$window" ] || { echo "could not infer a style from window-status-format" >&2; exit 1; }
  [ -n "$active" ] || { echo "could not infer a style from window-status-current-format" >&2; exit 1; }
  apply @agent_bar_style_window "$window"
  apply @agent_bar_style_window_active "$active"
  [ -n "$status_bg" ] && apply @agent_bar_status_bg "$status_bg"
fi
[ -n "$accent" ] && apply @agent_bar_accent "$accent"

[ "${#lines[@]}" -gt 0 ] || { echo "found nothing to match in the status line" >&2; exit 1; }

bash "$ROOT_DIR/agent-bar.tmux"

printf 'Applied. To keep it, add to tmux.conf above the plugin line:\n'
printf '  %s\n' "${lines[@]}"
