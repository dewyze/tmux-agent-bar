#!/usr/bin/env bash
# The parser and installer are two halves of one contract: every event the
# parser maps must be registered by the installer, or the mapping is dead
# code (Claude only invokes hooks for registered events). This drifted once.
. "$(dirname "$0")/../testlib.sh"

export HOME="$TEST_TMP/home"
mkdir -p "$HOME/.claude"
bash "$ROOT_DIR/scripts/install-claude-hooks.sh" >/dev/null

registered="$(python3 -c "
import json
print('\n'.join(json.load(open('$HOME/.claude/settings.json'))['hooks']))
")"

# Every event name string the parser matches on
mapped="$(grep -oE '"[A-Z][A-Za-z]+"' "$ROOT_DIR/lib/parse-claude.py" | tr -d '"' | sort -u)"

for event in $mapped; do
  case "$registered" in
    *"$event"*) ;;
    *) fail "parser maps '$event' but installer never registers it" ;;
  esac
done
