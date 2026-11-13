#!/usr/bin/env bash
# Codex CLI hook entry point. All writer behavior lives in run_agent_hook.
#
# Codex's shared background server (`daemon_auto_start`, on by default)
# runs every session's hooks itself, with the environment of the pane that
# first started it: TMUX_PANE then names the wrong pane, or a dead one
# (openai/codex#48500). That server has no terminal; a Codex running its
# own hooks (`codex --no-daemon`) does. So no terminal on the parent means
# no way to know the pane, and nothing is written.
case "$(ps -o tty= -p "$PPID" 2>/dev/null)" in
  ""|*\?*) exit 0 ;;
esac
case "$0" in */*) here="${0%/*}" ;; *) here=. ;; esac
. "$here/../lib/hook-lib.sh"
run_agent_hook codex "$@"
