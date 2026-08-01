# The @agent_* pane-option schema, version 1

A contract for reporting AI-agent status through tmux pane user options.
The tmux server is the store: any producer can put an agent on any
consumer's display with one `set-option -p`, no daemon, no IPC, no
registration — and state dies with its pane, so cleanup is structural.
tmux-agent-bar is the reference producer (Claude Code) and consumer (the
status-line bar), but the schema is deliberately independent of both.

## Options

All options are **pane** user options (`tmux set-option -p`). Never write
them at server scope (`-s`): server-global options shadow pane values for
every consumer reading via formats.

| Option | Required | Value |
|---|---|---|
| `@agent_schema` | yes | schema version this producer speaks; currently `1` |
| `@agent_app` | yes | producer identity: `claude`, `codex`, ... (lowercase token) |
| `@agent_state` | yes | one of the closed vocabulary below |
| `@agent_updated` | yes | epoch seconds of the last write |
| `@agent_subagents` | no | live subagent refcount (see state machine) |
| `@agent_transcript` | no | absolute path to the producer's transcript/log, if it keeps one |
| `@agent_writer_version` | no | producer's own version, for install-skew diagnosis |

## State vocabulary (closed — new states require a schema version bump)

| State | Meaning | Exits via |
|---|---|---|
| `running` | agent is working | events |
| `subagent-running` | working, with live subagents (`@agent_subagents` > 0) | events |
| `needs-input` | blocked on the human (permission, question) | events, or evidence-based verification (below) |
| `done` | finished, human hasn't seen it | consumer acknowledgement (below) |
| `error` | died abnormally | events, or manual clear |
| `idle` | alive, waiting for instructions | events |
| *(unset)* | no agent in this pane | — |

`idle` is a **state, not an absence**: consumers should render idle agents
(dimly). Unset means gone; the only transitions to unset are the producer's
exit event and pane death.

## Producer obligations

- Write only panes you own (the pane your agent runs in; `$TMUX_PANE`).
- Batch multi-option writes into one tmux invocation — each `set-option`
  triggers a full client redraw.
- On agent exit, **unset every `@agent_*` option** rather than writing a
  state. A dead agent has no state.
- Timestamps are epoch seconds, producer's host clock.
- Subagent lifecycle, if reported, must follow the shared state machine
  (`resolve_agent_state` in `lib/hook-lib.sh`): start increments and forces
  `subagent-running`; stop decrements (a stop at refcount 0 is stale and
  must not write); "soft" activity respects the refcount; terminal states
  (`running`/`done`/`idle` from non-subagent events) drain it.

## Consumer rules

- Read via formats (`#{@agent_state}`) or `show-options -pv`. Never poll
  processes; option writes already trigger redraws.
- **Clearing another producer's `needs-input` requires positive evidence.**
  The reference implementation reads the transcript named by
  `@agent_transcript` and clears only when a conversation entry postdates
  `@agent_updated`. A consumer with no evidence path must leave the badge.
- `done` is an attention flag: a consumer may clear it to `idle` once the
  human has demonstrably seen the pane (e.g. selected it).
- Ignore options from schema versions you don't speak (`@agent_schema`
  mismatch) rather than misinterpreting them.

## Versioning

`@agent_schema` is bumped for: new required options, new states, changed
semantics of existing states. Adding *optional* options is not a bump.
Producers stamp the version on every write; consumers may warn on mismatch.

## Conformance

A producer is conformant if: every write includes `@agent_schema`,
`@agent_app`, `@agent_state` (from the vocabulary), and `@agent_updated`;
exit unsets everything; subagent reporting follows the state machine.
The reference test suites (`tests/hooks/state_machine_test.sh`,
`tests/hooks/hook_claude_tmux_test.sh`) are the executable spec.

## Example: any script as a producer

```sh
tmux set-option -p -t "$TMUX_PANE" @agent_schema 1 \; \
  set-option -p -t "$TMUX_PANE" @agent_app build \; \
  set-option -p -t "$TMUX_PANE" @agent_state running \; \
  set-option -p -t "$TMUX_PANE" @agent_updated "$(date +%s)"
# ... long-running work ...
tmux set-option -p -t "$TMUX_PANE" @agent_state done \; \
  set-option -p -t "$TMUX_PANE" @agent_updated "$(date +%s)"
```

That is the entire API: your test run, deploy, or backup now badges the
bar like any agent.
