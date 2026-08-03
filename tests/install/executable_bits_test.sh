#!/usr/bin/env bash
# tmux run-shell and Claude Code hooks execute these by path via sh -c; a
# missing exec bit fails silently at server start. Tests invoke scripts with
# `bash path` and can't catch it, so guard the bits explicitly.
. "$(dirname "$0")/../testlib.sh"

for script in \
  "$ROOT_DIR/agent-bar.tmux" \
  "$ROOT_DIR/hooks/claude.sh" \
  "$ROOT_DIR/scripts/jump.sh" \
  "$ROOT_DIR/scripts/verify-needs-input.sh" \
  "$ROOT_DIR/scripts/reset.sh" \
  "$ROOT_DIR/scripts/adopt-theme.sh" \
  "$ROOT_DIR/scripts/install-claude-hooks.sh"; do
  [ -x "$script" ] || fail "not executable: $script"
done
