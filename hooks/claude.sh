#!/usr/bin/env bash
# Claude Code hook entry point. All writer behavior lives in run_agent_hook.
. "$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)/lib/hook-lib.sh"
run_agent_hook claude "$@"
