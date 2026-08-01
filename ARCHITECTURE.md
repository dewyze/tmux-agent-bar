# Architecture

The design constraint everything follows from: **the tmux server is the
database, formats are the view, and no process of ours stays resident.**
State lives in pane user options (`@agent_*`), which are free, atomic per
write, readable from any format, and die with their pane — cleanup is a
property, not a feature.

## Data flow

```
                        WRITE PATH (event-driven, per hook event)
┌──────────────┐  JSON on stdin   ┌──────────────────┐ state/subagent/transcript
│ Claude Code  │ ───────────────► │ hooks/claude.sh  │ ◄── lib/parse-claude.py
│ (any harness)│   12 lifecycle   │ (thin IO wrapper)│      (pure: event → state)
└──────────────┘      events      └────────┬─────────┘
                                           │ one batched `tmux set-option -p`
                                           ▼
                        ┌─────────────────────────────────────┐
                        │ tmux server: pane user options       │
                        │ @agent_app @agent_state              │
                        │ @agent_subagents @agent_updated      │
                        │ @agent_transcript                    │  ◄── any other
                        └────────┬────────────────┬───────────┘      producer may
                                 │                │                  write these
              READ PATH (render) │                │ READ PATH (truth check)
                                 ▼                ▼
                  ┌───────────────────────┐   ┌──────────────────────────────┐
                  │ status-format[1]      │   │ navigation hooks [181-183]   │
                  │ (lib/bar-format.sh    │   │ done → idle (pure tmux)      │
                  │ bakes it at load; the │   │ needs-input → verify against │
                  │ server re-expands it  │   │ transcript tail              │
                  │ on every option write)│   │ (scripts/verify-needs-input  │
                  └───────────┬───────────┘   │  + lib/transcript-progressed)│
                              │               └──────────────────────────────┘
                              ▼
                  ┌───────────────────────┐       INTERACTION PATH
                  │ status line 1: badges │  clicks (MouseDown1/3Status)
                  │ #[range=user|%id] ... │ ─────► scripts/jump.sh (navigate)
                  └───────────────────────┘        scripts/menu.sh (display-menu)
```

Key properties:

- **Zero polling.** Writes trigger tmux's own redraw (`options_push_changes`
  redraws clients on any option set). The bar updates the instant a hook
  fires; nothing ticks.
- **Zero resident processes.** Every box above is either the tmux server
  itself or a short-lived process spawned by an event (hook fire, navigation
  with a `?` present, a click).
- **Clearing requires positive evidence.** `needs-input` falls only to a
  conversation entry (`user`/`assistant`, non-meta) newer than the badge;
  `done` falls to being seen. Every failure mode keeps the badge — no
  transcript recorded, unreadable/rotated file, foreign agent, an answer
  buried beyond the 64KB tail window. Accepted consequence: those cases can
  pin a stale `?` until the next hook event or a manual menu-clear; we trade
  that for never clearing a live prompt.
- **The schema is the API.** Any producer can put a pane on the bar with
  one `tmux set-option -p` — no IPC, no daemon, no registration.

## Module architecture

Layered; each layer knows only the one below it.

| Layer | Files | Responsibility | May touch tmux? |
|---|---|---|---|
| **Contract** | README schema section (future `SCHEMA.md`) | `@agent_*` names, state vocabulary, who writes/clears what | — |
| **Parsers** (pure) | `lib/parse-claude.py` | harness payload → `(state, subagent_event, transcript)`; one file per harness, no side effects, no tmux | never |
| **Writer** | `hooks/claude.sh`, `lib/hook-lib.sh` | stdin/argv plumbing, pane identity (`TMUX_PANE`), subagent refcount state machine, batched option writes, trace | writes options |
| **Store** | tmux server (pane user options) | the entire runtime state | is tmux |
| **View** (pure) | `lib/bar-format.sh` | emits the format string; glyphs, styles, ranges, label rules | never (string out) |
| **Verifiers** | `scripts/verify-needs-input.sh`, `lib/transcript-progressed.py` | reconcile stored state against external truth (transcript) | reads + one write |
| **Interactions** | `scripts/jump.sh`, `scripts/menu.sh` | one action per file, argv pre-validated, no format context | commands |
| **Composition root** | `agent-bar.tmux` | wires view into `status-format[1]`, binds mouse + navigation hooks; the only file that installs anything | config |
| **Distribution** | `.claude-plugin/` + `hooks/hooks.json` (packaged path, primary), `scripts/install-claude-hooks.sh` (settings fallback) | register the writer with the harness; both paths must declare identical events (drift-guarded by test). The packaged writer runs from Claude's copy of the repo, so it stamps `@agent_writer_version` (from `VERSION`) to make copy/checkout skew observable; `scripts/reset.sh` restores a clean state | — |

Rules that keep the layering honest:

1. Parsers are pure functions with a 3-line stdout protocol; adding a harness
   means adding `lib/parse-<app>.py` + `hooks/<app>.sh` and nothing else.
2. The state machine (refcount, reset guard, stale-stop guard) lives in the
   writer, keyed by parser markers (`start`/`stop`/`soft`) — parsers know
   *what happened*, the writer knows *what it means for stored state*.
   Known debt, both honest: (a) when a second harness exists, this logic
   moves to `lib/hook-lib.sh` so it isn't copy-pasted; (b) the refcount is a
   read-modify-write across two tmux invocations under async hooks — the one
   race in the system. Two simultaneous SubagentStarts can under-count; the
   reset guard makes it self-healing rather than sticky.
3. The view never computes: no counts, no sorting, no time math. The standing
   budget for `#()` helpers in the format is **one**, currently unspent.
4. Only the composition root claims shared tmux resources (format slot,
   hook indices 181–183, mouse bindings), so installing is one file's
   concern. (Uninstall on the tmux side does not exist yet — removing the
   repo leaves hooks 181–183 firing at dead paths until server restart.
   Open finding, not a property.)

## Testing model

Two rails per component: stub-tmux suites (PATH shim records exact commands)
for logic, real-server suites (private `-L` sockets) for behavior, plus a
nested-tmux capture test proving the bar draws. Contract drift is guarded by
tests: parser events ⊆ registered events; plugin hooks.json ≡ settings
installer; exec bits on every entry point invoked by path.
