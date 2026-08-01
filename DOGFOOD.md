# QA checklist (round 2)

Each item is *action → expected*. Anything else is a bug: note the time and
pane, then read the trace. Trace must be armed: `tmux show -gv
@agent_bar_trace` — set it (and re-arm after any server restart) or add it
to tmux.conf.

Round 1 verified the core lifecycle and the needs-input contract
(approve/deny/false-clear all passed); this round covers everything built
since, plus the two items round 1 left unchecked.

## Rendering & grouping

- [ ] Bar reads `║ win │ * claude ...` — heavy bar opens each window group,
      thin divider before each agent, no whitespace-only separators anywhere
- [ ] Nerdfont theme active (from tmux.conf): dividers are powerline
      chevrons ( filled for groups,  thin for panes), not `║`/`│`
- [ ] Two agents in one window → one window label, two glyphs inside the
      group, each independently clickable
- [ ] Badge text is `claude` by default — never a pane title, never a
      command, never a hostname
- [ ] Rename (right-click → Rename, or `tmux set -p @agent_name reviewer`)
      → badge text becomes the name; empty rename → back to `claude`
- [ ] Name survives restarting claude in that pane (user-owned)
- [ ] Foreign-session groups (make a scratch session with an agent) show
      `session/window` label; your own session's groups show bare window
      names

## Leftovers from round 1

- [ ] Kill a pane while its agent runs → badge gone (pane death = cleanup)
- [ ] `?` survives the 60s idle nudge while you're away

## Mouse (both halves)

- [ ] Left-click badge from another window/session → lands on that pane
- [ ] Right-click badge → menu AT THE CLICK POINT; quick-click keeps it
      open; press-drag-release selects in one motion
- [ ] Menu items: Jump / Clear status / Rename / Kill (confirmed) all work
- [ ] **Defaults restored**: left-click a window NAME on line 0 → switches
      window; right-click line 0 → tmux's stock window menu (Swap/Kill/
      Rename/Respawn/New)
- [ ] Click a blank area of the agent line → nothing happens, nothing breaks

## Options (spot-check the seam)

- [ ] `tmux set -g @agent_bar_glyph_running R` + re-run `agent-bar.tmux`
      → glyph changes; unset + re-run → back to `*`
- [ ] `tmux set -g @agent_bar_name_max 4` + re-run → names truncate
- [ ] `tmux set -g @agent_bar_mouse off` + `scripts/reset.sh` → badge
      clicks dead, line-0 defaults still fine (then turn it back on)

## Ops

- [ ] `scripts/reset.sh` → all badges cleared (including names), bar and
      bindings reapplied, version printed; agents re-badge on next event
- [ ] tmux server restart → bar returns from conf (nerdfont theme intact),
      badges repopulate as agents emit events; re-arm the trace
- [ ] `tmux show -pv @agent_writer_version` on an active agent pane matches
      `VERSION`; `@agent_schema` reads `1`
- [ ] Subagent-heavy prompt → `**` while subagents live, `*` after; a
      finished turn's `+`/`·` never resurrects to `*`

## Packaging (never tested — the big open item)

- [ ] `/plugin marketplace add ~/dev/tmux-agent-bar` + `/plugin install
      tmux-agent-bar@tmux-agent-bar`; REMOVE the settings.json entries
      (else events double-fire); restart a claude → badges work
- [ ] Async check on the packaged path: claude must not visibly stall on
      prompts/tool calls (a stall = plugin hooks ignore `async: true` →
      settings path stays primary)
- [ ] `claude plugin uninstall` → hooks stop firing, settings untouched

Highest-signal: line-0 defaults, the rename flow, and the entire
packaging section.
