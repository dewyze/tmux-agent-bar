# Side bar: vertical rendering via tmux `side-status`

Handoff for adding vertical-bar support alongside the existing horizontal
status-line rendering. Written 2026-08-03 by the session that built the tmux
feature this targets. The goal here is the *prep* refactor (make the change
easy) — the vertical mode itself lands later, once the tmux feature ships or
for dogfooding against the patched build.

**Status (2026-10-16):** done. Vertical mode shipped here, and the tmux
maintainer applied the feature upstream (tmux/tmux#5468, OpenBSD commit
a7e88010). It is on tmux master and ships in 3.9. The facts below are
updated to upstream; the plan sections are history.

## The tmux feature this targets

A vertical status line in tmux core, built per the maintainer's spec in
tmux/tmux#4910 and applied upstream from tmux/tmux#5468.

- To test, build tmux master (README, Vertical mode) and run it with
  `-Ldogfood` to stay off the daily server. The fork branch
  `vertical_status_line` in `~/dev/tmux` is finished; don't build against it.

Feature surface (final upstream names):

- `side-status` — `off`/`left`/`right`, session-scoped. Independent of
  `status`: both bars can be on at once. Bottom line keeps window names;
  side bar renders whatever `side-status-format` says.
- `side-status-width` — fixed column width, default 14. The edge line is
  drawn inside it. Dragging the edge sets a session value; double-clicking
  it unsets that value.
- `side-status-format` — a plain string, same vocabulary as
  `status-format`. A new `#[nl]` style (or a literal newline) ends the
  current row; it passes through format expansion untouched, so it can be
  emitted conditionally inside nested `#{S:#{W:#{P:...}}}` loops — one
  badge per row. Colours, attributes and an open `#[range=...]` carry
  across the break. A trailing `#[nl]` after the last badge is harmless
  (trailing empty rows are dropped).
- Rows drawn under `list=on` scroll to keep the `list=focus` row visible when
  there are more rows than fit; `list=left-marker`/`list=right-marker` rows
  replace the first/last visible list row when scrolled. agent-bar uses
  them: the current window is the focus.
- The bar disables itself on terminals narrower than its width and comes back
  on resize.

**Option names are final upstream.** They stay centralized at the top of
`agent-bar.tmux`, so a rename would still be a one-line change.

## Guarantees (what does NOT change)

- **Schema: untouched.** `@agent_app` / `@agent_state` / `@agent_subagents` /
  `@agent_updated` and the hook pipeline are orientation-agnostic. No hook,
  parser, or state change is needed for vertical rendering.
- **Mouse: untouched.** Side-bar clicks fire the same `MouseDown1Status` /
  `MouseDown3Status` (and `...StatusDefault`) bindings, and
  `#{mouse_status_range}` resolves `user|<pane_id>` ranges identically to the
  horizontal bar. This was a deliberate design constraint of the tmux branch.
  Jump and menu bindings work on both bars unmodified.
- **Format vocabulary: identical.** The badge (`#[range=user|#{pane_id}]` +
  state mark + label + `#[default norange]`) is valid side-bar content as-is.
  Only the *separator between badges* differs: `#[nl]` instead of spaces.

## Prep refactor (do now, on stock tmux, no dependency on the feature)

1. **Separate badge from layout.** The badge definition should be
    orientation-neutral; a thin layout wrapper joins badges with a separator
    (horizontal: the current spacing; vertical: `#[nl]`). Today the separator
    is baked into the badge string.
2. **Funnel installation through one target decision.** The plugin currently
    claims `status-format[1]` and raises `status`. Side mode must NOT do
    either — it sets `side-status` + `side-status-format` instead. Make
    "install the format into tmux" a single function with a single
    target-decision point, and make each mode able to cleanly undo the
    *other* mode's claims (mode switching at runtime). This is the subtle
    part: install/uninstall/toggle state management, including the existing
    "keep the user's `status` value if already 3+" nuance.
3. **Parameterize the render tests by orientation** (or at least factor the
    assertions) so vertical cases are additive, not copy-paste.

## The later easy change (after prep)

- `@agent_bar_position` option: `status` (default, today's behavior) /
  `left` / `right`.
- Vertical layout in the format emitter (badge join = `#[nl]`).
- Capability probe: attempt `set -g side-status` in a throwaway way; on
  failure (stock tmux), fall back to `status` mode. Safe to ship in dotfiles
  that hit both patched and stock machines.

## Known design considerations

- **Label economy.** A 24-column bar wants tighter labels than an unbounded
  horizontal strip: title truncation length, whether the session prefix is
  worth its columns, the group-by-session presentation. If per-orientation
  label tuning is wanted, the badge factoring needs a verbosity/width knob.
  (Vertical tree/indent guides need no tmux support — they are just
  box-drawing glyphs emitted by the format, `choose-tree` style.)
- **Multi-row pane status is a separate future thing.** Per-pane detail rows
  under each agent pane (`pane-border-status` with height > 1) is a distinct
  tmux feature that does not exist yet; the side bar does not provide it.
  Don't design against it here.

## Quick dogfood check (needs a tmux master build)

```sh
/path/to/master/tmux -Ldogfood new -A -s test
# inside:
set -g side-status left
set -g mouse on
set -g side-status-format '#{S:#{W:#{P:#{?#{@agent_state},#[range=user|#{pane_id}]* #{window_name}#[default norange]#[nl],}}}}'
```

Badges appear one per row for panes with a set `@agent_state`; left-click
fires `MouseDown1Status` with `#{mouse_status_range}` = the pane id.
