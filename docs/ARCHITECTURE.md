# How it is built

tmux-agent-bar keeps no process running and no files of its own. Each
agent's state is stored on its tmux pane, as pane options such as
`@agent_state`. tmux draws the bar from those options and redraws it
whenever one changes. When a pane closes, its state goes with it.

## What happens on an event

```
the agent (Claude Code, Codex)
  │  runs a hook, with a JSON payload
  ▼
hooks/<app>.sh  +  lib/parse-<app>.py      payload → state
  │  one tmux command
  ▼
pane options on the tmux server            @agent_state, @agent_app, ...
  │  tmux redraws
  ▼
the bar                                    a format string from lib/bar-format.sh
  │  a click
  ▼
tmux key bindings                          jump to the pane, or open the menu
```

Nothing runs between events. The hook is a short script that exits, and
everything after it is tmux.

## Where things are

- `lib/parse-<app>.py`, one per agent. It reads a hook payload and prints
  a state. It never touches tmux.
- `lib/hook-lib.sh`, shared by every agent. It takes the parser's answer
  and writes the pane options. It also counts running subagents,
  remembers which agent asked a question, and removes everything when the
  agent exits.
- `hooks/<app>.sh`, a few lines joining the two. This is what the agent
  calls.
- `lib/bar-format.sh` builds the bar's format string from the
  `@agent_bar_*` options, once, when the plugin loads.
- `agent-bar.tmux` is the plugin's entry point. It installs the format,
  the mouse bindings, and three tmux hooks that run when you move between
  panes.
- `scripts/` has the hook installers, `reset.sh` and `adopt-theme.sh`.
- [SCHEMA.md](SCHEMA.md) writes the pane options down as a contract, for
  anyone adding an agent or reading the state from elsewhere.

## Decisions worth knowing

**A `?` is cleared only on evidence.** Claude Code sends no event when
you deny a permission request, so a `?` could stay up for good. When you
move between panes, a small script (`scripts/verify-needs-input.sh`)
reads the end of the agent's transcript, and clears the `?` only if the
conversation has moved on since. If it can't tell, the `?` stays. A stale
`?` is the lesser harm; a missing one means an agent waits unseen.

**A `+` is cleared by looking.** A finished badge goes back to idle when
you visit its pane. tmux does this by itself, with no script.

**The bar does no work.** The format string only reads options. It does
not count, sort or run commands, which is why redrawing it is free. It is
also why sessions appear in tmux's own order.

**One known race.** Subagents are counted by reading the count and
writing it back. Two starting at the same instant can be counted as one,
so `**` may drop to `*` early. The count resets at the next turn.

**Codex's background server.** When Codex runs hooks from its shared
server, a hook cannot tell which pane it belongs to. It then writes
nothing, so no pane is mislabelled. See the README's Codex section.

## Tests

`bash tests/run.sh` runs everything. Most tests start a real tmux server
on a private socket and check the pane options, or the screen as drawn.
A few replace tmux with a stub and check the commands sent to it. One
adds a made-up agent using the two-file recipe, so that "adding an agent
is easy" stays true.
