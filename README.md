# tmux-agent-bar

A status line for your AI agents, native to tmux. Agent lifecycle hooks write
tmux pane user options; a second status line renders one clickable badge per
agent pane across all sessions. No daemon, no state files, no polling — the
tmux server is the database, formats are the view, and a state change redraws
the bar immediately.

```
[0] 0:vim  1:api*                                          14:23
* work:api   ? work:db   + home:notes
```

`*` running · `**` subagent running · `?` needs input · `!` error · `+` done

- **Left-click** a badge: jump to that pane (session, window, pane).
- **Right-click**: menu — jump, clear status, kill pane.
- **Navigate to an agent's pane**: acknowledges it (`needs-input`/`done` clear
  to idle; `running`/`error` persist).

## Requirements

tmux ≥ 3.2 (pane user options, format pane loops, clickable status ranges);
developed and tested on 3.7b. bash and python3 for the hook scripts.

## Install

TPM: `set -g @plugin 'dewyze/tmux-agent-bar'` — or manually:

```tmux
run-shell ~/dev/tmux-agent-bar/agent-bar.tmux
```

Then register the Claude Code hooks (edits `~/.claude/settings.json`, with
backups, idempotently):

```sh
./scripts/install-claude-hooks.sh
```

The plugin raises `status` to 2 and claims `status-format[1]`. If you already
run 3+ status lines your `status` value is kept, but line index 1 is still
taken by the bar.

## How it works

```
Claude Code hook event (JSON on stdin)
  → hooks/claude.sh → lib/parse-claude.py     event → state
  → tmux set-option -p @agent_app/@agent_state/@agent_subagents/@agent_updated
  → status-format[1] (lib/bar-format.sh)      S/W/P loops render badges
  → MouseDown1Status / MouseDown3Status       jump / menu
```

States: `running`, `subagent-running` (refcounted, with a reset guard so a
lost SubagentStop can't stick), `needs-input`, `done`, `error`, `idle`
(invisible). Pane options die with the pane, so cleanup is automatic.

## Adding another agent

The schema is the contract, not the code. Make your agent's hook mechanism
write these pane user options on its own lifecycle events and its panes appear
in the bar:

```sh
tmux set-option -p -t "$TMUX_PANE" @agent_app codex \; \
  set-option -p -t "$TMUX_PANE" @agent_state needs-input \; \
  set-option -p -t "$TMUX_PANE" @agent_updated "$(date +%s)"
```

Convention: add `hooks/<app>.sh` + `lib/parse-<app>.py` mirroring the Claude
pair.

## Development

```sh
bash tests/run.sh                # all suites; passing tests print nothing
bash tests/run.sh tests/parser/parse_claude_test.sh
```

Unit suites stub tmux on PATH and assert exact commands; integration suites
run a real tmux server on a private socket, including a nested-tmux capture
test that verifies the bar actually draws.

## Roadmap

- Auto-hide the bar when no agents are active
- More agents: codex, cursor, kiro, opencode, pi
- Desktop notifications on needs-input
- Staleness handling for lost Stop events (title cross-check)
- Aggregate widgets ("3 waiting") via a persistent `#()` helper
- Nerd-font icon themes
- A native vertical status line in tmux itself (tmux/tmux#4910) — this bar's
  format and schema are designed to move there unchanged
