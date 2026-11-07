#!/usr/bin/env bash
# Claude Code hook entry point. All writer behavior lives in run_agent_hook.
case "$0" in */*) here="${0%/*}" ;; *) here=. ;; esac
. "$here/../lib/hook-lib.sh"
run_agent_hook claude "$@"
