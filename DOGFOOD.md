# Dogfood checklist

Each item is *action → expected*. Anything else is a bug: note the time and
pane, then read the trace (`tmux set -g @agent_bar_trace <file>` must be set —
re-arm after any server restart).

## Lifecycle basics (fresh `claude` in a new pane)

- [ ] Start claude → dim `·` badge appears immediately (SessionStart)
- [ ] Submit a prompt → `·` flips to `*` on submit, not on first output
- [ ] Let it finish → `+`; navigate to the pane → `+` clears to `·`
      (not to nothing — the pane stays on the roster)
- [ ] Exit claude → badge disappears entirely — the *only* way a badge
      should ever vanish
- [ ] Kill the pane while running → badge gone (pane death = cleanup)

## The needs-input contract

- [ ] Provoke a permission prompt → `?` within a beat
- [ ] While `?` is up: leave, return, stare, wait out the 60s idle nudge →
      `?` survives all of it
- [ ] **Approve** → `?` flips to `*` as the tool executes (PostToolUse)
- [ ] **Deny**, then navigate anywhere → `?` clears to `·` on that first
      navigation (transcript-verified)
- [ ] Deny and *don't* navigate → badge holds until you move; confirm that
      feels acceptable in practice
- [ ] False-clear guard: `?` up in pane A; in another pane *of the same
      project*, edit/save a file and navigate around → A's `?` must NOT
      clear (checkpoint entries are not evidence)
- [ ] Deny-with-instructions → `?` → `*` when it starts on your instruction

## Interactions

- [ ] From a different window, left-click a badge → lands on that pane;
      repeat from a different session
- [ ] Left-click a *window name on line 0* → still switches windows;
      right-click line 0 → tmux's window menu still appears.
      KNOWN-RISK: review finding #1 says our bindings ate these defaults —
      if line-0 clicking is dead, that confirms it (fix queued)
- [ ] Right-click a badge → menu at click point; Jump / Clear status /
      Kill pane (confirmed) all work

## Multi-agent roster

- [ ] 2–3 claudes across sessions/windows → all badged; current-session
      labels show `window` only, foreign show `session:window`; claude-set
      pane titles append truncated
- [ ] Subagent-heavy prompt → `**` during subagents, `*` after; a `+`/`·`
      badge never resurrects to `*` after the turn ended (stale-stop guard)

## Ops / packaging

- [ ] `scripts/reset.sh` → all badges cleared, bar/bindings reapplied,
      prints checkout version; live agents re-badge on next event
- [ ] Packaged path: `/plugin marketplace add <repo>` + `/plugin install`;
      REMOVE the settings.json entries (or events double-fire); restart a
      session → badges work; `tmux show -pv @agent_writer_version` matches
      `VERSION`
- [ ] Async check on the packaged path: claude must not visibly stall on
      prompts/tool calls — a stall means plugin hooks ignore `async: true`
      and the settings path stays primary
- [ ] Restart the tmux server → bar returns from the conf line; badges
      empty until agents emit events; re-arm `@agent_bar_trace`

Highest-signal items: deny-then-navigate, the false-clear guard, line-0
clicks, and the packaged async check.
