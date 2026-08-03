# tmux-agent-bar

A status line for your AI agents, native to tmux. Agent lifecycle hooks write
tmux pane user options; a second status line renders one clickable badge per
agent pane across all sessions. No daemon, no state files, no polling — the
tmux server is the database, formats are the view, and a state change redraws
the bar immediately.

```
[0] 0:vim  1:api*                                          14:23
║ win1 │ * fixing tests │ ? review auth ║ win2 │ ·  ║ blog/api │ +
```

`*` running · `**` subagent running · `?` needs input · `!` error ·
`+` done · `·` idle (alive, waiting). A badge disappears only when its
agent exits. Agents group under one window label; foreign sessions
prefix `session/`.

- **Left-click** a badge: jump to that pane (session, window, pane).
- **Right-click**: menu at the click — jump, clear status, rename, kill
  pane. Badge text: your rename → the harness's instance name → the
  harness (`claude`, `codex`, ...).
  Non-badge status clicks fall through to tmux's defaults.
- **Navigate to an agent's pane**: acknowledges `+` (clears to `·`).
  `?` is truthful state — it persists until the prompt is actually
  answered (event- or transcript-verified).

## Requirements

tmux ≥ 3.2 (pane user options, format pane loops, clickable status ranges);
developed and tested on 3.7b. bash and python3 for the hook scripts.

## Install

TPM: `set -g @plugin 'dewyze/tmux-agent-bar'` — or manually:

```tmux
run-shell ~/dev/tmux-agent-bar/agent-bar.tmux
```

Then register the Claude Code hooks. Preferred: install as a Claude Code
plugin (clean install *and* uninstall, no settings surgery):

```
/plugin marketplace add dewyze/tmux-agent-bar   # or the local repo path
/plugin install tmux-agent-bar@tmux-agent-bar
```

Alternative for setups without plugin support — edits `~/.claude/settings.json`
directly (idempotent, with rotated backups):

```sh
./scripts/install-claude-hooks.sh
```

Use one path or the other, not both, or every event fires the hook twice.
Both register the same events (a test enforces it). Hooks load at Claude
session start; restart sessions (or `/reload-plugins`) after installing.

The plugin path runs hooks from Claude's installed *copy* of this repo,
while tmux renders from your checkout/TPM clone. The hook stamps
`@agent_writer_version` on every write so skew between the two is
observable. After updating either side: `claude plugin update
tmux-agent-bar`, then `scripts/reset.sh` (clears all agent state and
reapplies the bar), then restart agent sessions.

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
(dim — a live agent waiting). Unset means gone; pane options die with the
pane, so cleanup is automatic. Full contract: [SCHEMA.md](SCHEMA.md).

## Configuration

Set options before the plugin loads (re-run `agent-bar.tmux` or
`scripts/reset.sh` to apply changes):

| Option | Default | |
|---|---|---|
| `@agent_bar_theme` | `ascii` | `nerdfont` uses powerline dividers |
| `@agent_bar_line` | `1` | which status line the bar claims |
| `@agent_bar_mouse` | `on` | `off` leaves mouse keys entirely untouched |
| `@agent_bar_pane_separator` | ` │ ` | between agents in a group |
| `@agent_bar_group_separator` | ` ║ ` | opens each window group |
| `@agent_bar_label_suffix` | *(empty)* | e.g. `:` for colon grammar |
| `@agent_bar_cross_session` | `inline` | `line`: foreign agents on their own status line, compact; `off`: local only |
| `@agent_bar_session_marker` | ` ▌ ` | accent marker introducing a foreign session |
| `@agent_bar_name_max` | `24` | badge-name truncation |
| `@agent_bar_glyph_<state>` | `* ** ? + ! ·` | per-state glyph overrides |
| `@agent_bar_style_window` | `fg=colour243` | inactive window-group style (space-separated) |
| `@agent_bar_style_window_active` | `fg=colour250 bold` | active window-group style — follows the active window |
| `@agent_bar_accent` | `colour109` | session marker/name colour |

`scripts/adopt-theme.sh` infers the three style options from your existing
`window-status-format`s and `status-left`, applies them, and prints the
lines to add to tmux.conf.
| `@agent_bar_trace` | *(unset)* | file path enables hook event tracing |

## Adding another agent

The contract is [SCHEMA.md](SCHEMA.md) — versioned, with producer and
consumer rules; any script can join the bar with one `set-option`.
For a full integration, the recipe is two files:

1. `lib/parse-<app>.py` — pure: payload in `$HOOK_PAYLOAD` → three lines on
   stdout: state, subagent event (`start`/`stop`/`soft`/empty), transcript
   path (or empty). Unknown events print nothing.
2. `hooks/<app>.sh` — three lines:

   ```sh
   #!/usr/bin/env bash
   . "$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)/lib/hook-lib.sh"
   run_agent_hook <app> "$@"
   ```

Schema stamping, the subagent state machine, exit-unsets, and tracing all
come from `run_agent_hook`. Wire your harness to invoke the wrapper on its
lifecycle events, and its panes appear on the bar.
`tests/hooks/new_harness_test.sh` is this recipe, executable.

For anything simpler — a build, a deploy — skip the recipe and write the
options directly per SCHEMA.md:

```sh
tmux set-option -p -t "$TMUX_PANE" @agent_schema 1 \; \
  set-option -p -t "$TMUX_PANE" @agent_app build \; \
  set-option -p -t "$TMUX_PANE" @agent_state running \; \
  set-option -p -t "$TMUX_PANE" @agent_updated "$(date +%s)"
```

## Recipes: agent state in your own status line

The schema is readable from any tmux format — these need nothing from the
plugin's bar (all verified against a live server). The building block is a
pane probe: "does any pane in this window have agent state X":

```
#{?#{P:#{?#{==:#{@agent_state},needs-input},x,}},<yes>,<no>}
```

**Window-list flag** — a dot in your `window-status-format` when a window
contains an agent waiting for input (style attrs inside conditionals use
spaces, never commas — commas would split the conditional):

```tmux
setw -g window-status-format ' #I #{?#{P:#{?#{==:#{@agent_state},needs-input},x,}},#[fg=yellow bold]● #[default],}#W '
```

**Status-corner aggregate** — "any agent anywhere needs me", for
`status-left`/`status-right` (spans all sessions):

```tmux
set -ga status-right '#{?#{S:#{W:#{P:#{?#{==:#{@agent_state},needs-input},x,}}}},#[fg=yellow bold] ● agents ,}'
```

**Pane border badge** — the agent's state on its own pane border:

```tmux
set -g pane-border-status top
set -g pane-border-format ' #{pane_index} #{?#{@agent_state},#[fg=cyan]#{@agent_state} ,}'
```

Note: a bare `#{@agent_state}` in a window-list entry resolves against that
window's *active pane* only — the `#{P:...}` probe is what makes it "any
pane in the window".

## Development

```sh
bash tests/run.sh                # all suites; passing tests print nothing
bash tests/run.sh tests/parser/parse_claude_test.sh
```

Unit suites stub tmux on PATH and assert exact commands; integration suites
run a real tmux server on a private socket, including a nested-tmux capture
test that verifies the bar actually draws.

## Roadmap

Ranked by expected daily leverage:

1. **Remote approve/deny** — right-click a `?` badge → Approve/Deny items
   `send-keys` the answer into the prompt; handle permissions from any window
   without visiting the pane. The badge becomes a control surface.
2. **Desktop notifications on needs-input** — the hook knows the moment;
   `terminal-notifier` banner, deep-link click back to the pane.
3. **Waiting-duration on badges** (`? api 4m`) — `@agent_updated` is already
   recorded; needs the first persistent `#()` helper (formats can't do
   now-minus-then).
4. **Attention-first ordering** — formats can't sort; same `#()` helper as
   duration.
5. **Hookless agent detection** — panes running `claude`/`codex` without
   hooks installed still get a dim badge via command-name heuristics.
6. **More agents** — codex, cursor, kiro, opencode, pi via the pane-option
   contract.
7. **Colors/icons pass** — current palette is placeholder; nerd-font themes.
8. **Upstream: `PermissionResolved` hook event in Claude Code** — denials
   emit no event today; this would delete `verify-needs-input.sh`.
9. **A native vertical status line in tmux itself** (tmux/tmux#4910) — this
   bar's format and schema are designed to move there unchanged.

Dropped: auto-hide when empty (idle badges mean the bar is never empty).
