# tmux-agent-bar

Shows your AI coding agents in a tmux side bar. Each agent gets a small
badge that says whether it is working, finished, or waiting on you. Click
a badge to jump to that agent.

<img src="https://github.com/user-attachments/assets/a7c7b642-4376-438a-84cf-5fa19019bb33" alt="A tmux window with a side bar on the left listing sessions and windows. Agents appear under their window with a badge: a yellow ? for one waiting on input, a green + for one that finished, dim dots for idle ones." />

It is meant to be efficient and plain. There is no daemon and nothing
polls. When an agent changes state, its hook writes a few tmux options and
tmux redraws the bar. Between events nothing runs.

It works with Claude Code and Codex CLI.

## Install

You need:

- tmux 3.9 or newer. 3.9 is not released yet, so for now that means a
  build of tmux's master branch. See step 1.
- bash and python3, for the hooks.

### 1. tmux

The side bar is a new tmux feature
([tmux/tmux#5468](https://github.com/tmux/tmux/pull/5468)). It is in
tmux's master branch and will ship in 3.9.

With Homebrew you can get it now:

```sh
brew uninstall tmux
brew install --HEAD tmux
```

On other systems, follow "From version control" in tmux's
[install guide](https://github.com/tmux/tmux/wiki/Installing).

A running tmux server keeps the old version until it exits. Check what
you are running with `tmux display -p '#{version}'`. `tmux kill-server`
closes every session and starts fresh on the new one.

### 2. The plugin

With [TPM](https://github.com/tmux-plugins/tpm), add to `tmux.conf`:

```tmux
set -g mouse on
set -g @agent_bar_position left
set -g @plugin 'dewyze/tmux-agent-bar'
```

Without TPM:

```sh
git clone https://github.com/dewyze/tmux-agent-bar ~/.tmux/plugins/tmux-agent-bar
```

```tmux
set -g mouse on
set -g @agent_bar_position left
run-shell ~/.tmux/plugins/tmux-agent-bar/agent-bar.tmux
```

`mouse on` is only needed for clicking. Use `right` to put the bar on the
other side.

### 3. Hooks for your agent

The bar only shows agents that report to it. Set up the ones you use.

**Claude Code.** Install it as a Claude Code plugin. In Claude:

```
/plugin marketplace add dewyze/tmux-agent-bar
/plugin install tmux-agent-bar@tmux-agent-bar
```

If you would rather not use Claude plugins, this script adds the same
hooks to `~/.claude/settings.json` and keeps a backup:

```sh
./scripts/install-claude-hooks.sh
```

Use one or the other. With both, every event is reported twice. Restart
your Claude sessions afterwards.

**Codex CLI.**

```sh
./scripts/install-codex-hooks.sh
```

This adds the hooks to `~/.codex/hooks.json` and keeps a backup. Then two
more steps:

1. Run `/hooks` inside Codex and approve them. Codex ignores new hooks
   until you do.
2. Turn off Codex's shared background server. Add this to
   `~/.codex/config.toml`:

   ```toml
   [features]
   daemon_auto_start = false
   ```

   or start Codex with `codex --no-daemon`.

The second step is a workaround for a Codex bug
([openai/codex#48500](https://github.com/openai/codex/issues/48500)).
With the background server on, hooks cannot tell which pane they belong
to, so the plugin shows no Codex badges at all. That seemed better than
showing them on the wrong pane.

Codex also reports a little differently from Claude Code. A badge appears
at the first prompt, not when Codex starts, and it can stay for up to a
minute after Codex quits.

Now start an agent in any pane and its badge should appear.

### Updating

Update the plugin the way you installed it (TPM, or `git pull`). If you
installed the Claude Code plugin, also run
`claude plugin update tmux-agent-bar`. Then:

```sh
./scripts/reset.sh
```

It clears all badges and reloads the bar. Restart your agents after that.

### Uninstalling

1. Claude Code: `/plugin uninstall tmux-agent-bar@tmux-agent-bar`. If you
   used the script, delete the entries that run `hooks/claude.sh` from
   `~/.claude/settings.json`.
2. Codex: delete the entries that run `hooks/codex.sh` from
   `~/.codex/hooks.json`.
3. tmux: remove the plugin lines from `tmux.conf` and restart the server
   with `tmux kill-server`.

## The bar

The bar lists every session and its windows. Agents sit under the window
they run in.

| Badge | Meaning |
|---|---|
| `*` | working |
| `**` | working, with subagents running |
| `?` | waiting on you |
| `+` | finished |
| `!` | stopped on an error |
| `·` | idle |

A few things about how the badges behave:

- `?` stays until that agent has its answer. Other activity in the same
  pane, such as a subagent still working, does not clear it.
- `+` means "finished and you have not looked yet". It turns into `·` when
  you visit the pane, and it never shows for the pane you are looking at.
- A badge goes away when its agent exits.
- An agent is listed by its app name (`claude`, `codex`) until you give it
  a name of your own.

Clicking:

- Left-click a badge to go to that agent's session, window and pane.
- Left-click a window or a session name to go there.
- Right-click a badge for a small menu: jump, clear status, rename, kill
  pane.

When the list is taller than the screen it scrolls, and keeps the current
window in view.

> **Screenshot to add:** the right-click menu open on a badge.

> **Screenshot or GIF to add:** an agent going from `*` to `?`, then a
> click that jumps to it.

## How it works

Claude Code and Codex can run a command on events such as "prompt
submitted", "permission requested" and "turn finished". This plugin
registers one small script for those events. The script works out the
agent's state and stores it on the tmux pane as a user option, for
example `@agent_state needs-input`.

The bar is a tmux format string that reads those options. tmux redraws it
when an option changes. Clicks are ordinary tmux key bindings.

That is the whole thing. State lives in the tmux server, so there are no
state files to go stale, and closing a pane cleans up after itself.

[SCHEMA.md](SCHEMA.md) lists the pane options. [ARCHITECTURE.md](ARCHITECTURE.md)
explains the design in more detail.

## Bottom bar

The plugin can also draw the agents on a second status line at the
bottom. This works on released tmux (3.2 and newer). It is what you get
if you leave out `@agent_bar_position`, or if your tmux has no side bar.

```
[0] 0:vim  1:api*                                          14:23
║ win1 │ * fixing tests │ ? review auth ║ win2 │ · ▌ blog ║ api │ +
```

It works, but it is not a priority. I use the side bar, so that is where
the attention goes. Pull requests for the bottom bar are welcome.

## Configuration

Options are tmux options. Set them in `tmux.conf` above the plugin line:

```tmux
set -g @agent_bar_width 30
```

Then reload your `tmux.conf`, or run `./scripts/reset.sh`.

### Layout

| Option | Default | What it does |
|---|---|---|
| `@agent_bar_position` | `status` | `left` or `right` for the side bar. `status` is the bottom bar. |
| `@agent_bar_width` | `24` | Width of the side bar, in columns. |
| `@agent_bar_cross_session` | `inline` | `off` shows only the session you are in. |

### Badges and names

| Option | Default | What it does |
|---|---|---|
| `@agent_bar_glyph_running` | `*` | Badge for a working agent. |
| `@agent_bar_glyph_subagent_running` | `**` | Badge while subagents run. |
| `@agent_bar_glyph_needs_input` | `?` | Badge for an agent waiting on you. |
| `@agent_bar_glyph_done` | `+` | Badge for a finished agent. |
| `@agent_bar_glyph_error` | `!` | Badge for an error. |
| `@agent_bar_glyph_idle` | `·` | Badge for an idle agent. |
| `@agent_bar_name_max` | `24` | Longest agent name shown before it is cut. |
| `@agent_bar_label_suffix` | empty | Text after each window name, such as `:`. |
| `@agent_bar_session_marker` | ` ▌ ` | Mark in front of a session name. |

### Colours

| Option | Default | What it does |
|---|---|---|
| `@agent_bar_style_window` | `fg=colour243` | Style of window names. |
| `@agent_bar_style_window_active` | `fg=colour250 bold` | Style of the current window's name. |
| `@agent_bar_accent` | `colour109` | Colour of session names. |

Styles use tmux's style syntax, with spaces between parts and no commas.

The side bar's own background and text colour belong to tmux, not to the
plugin. Set them with tmux's `side-status-style`:

```tmux
set -g side-status-style "bg=colour236,fg=colour254"
```

### Mouse and keys

| Option | Default | What it does |
|---|---|---|
| `@agent_bar_mouse` | `on` | `off` leaves all mouse bindings alone. |

The plugin binds no keys. Two bindings you may want:

```tmux
# Show or hide the side bar
bind-key b if-shell -F '#{==:#{side-status},off}' 'set -g side-status left' 'set -g side-status off'

# Name the agent in the current pane (an empty name goes back to the app name)
bind-key A command-prompt -I '#{@agent_name}' -p 'Agent name:' { set-option -p @agent_name '%%' }
```

### Bottom bar only

| Option | Default | What it does |
|---|---|---|
| `@agent_bar_line` | `1` | Which status line the bar takes. |
| `@agent_bar_theme` | `ascii` | `nerdfont` uses powerline dividers. |
| `@agent_bar_pane_separator` | ` │ ` | Between agents in a window. |
| `@agent_bar_group_separator` | ` ║ ` | In front of each window. |
| `@agent_bar_cross_session` | `inline` | `line` puts other sessions on a line of their own. |
| `@agent_bar_status_bg` | unset | Status line background, for powerline segments. |
| `@agent_bar_divider_fg` | `colour240` | Colour of the thin dividers. |

`./scripts/adopt-theme.sh` tries to copy the colours of your existing
status line onto the bottom bar and prints the lines to keep.

### Debugging

| Option | Default | What it does |
|---|---|---|
| `@agent_bar_trace` | unset | Path of a file to log every hook event to. |

## Adding another agent

An agent needs two small files: a parser that turns its hook payload into
a state, and a four-line wrapper script. `lib/parse-codex.py` and
`hooks/codex.sh` are a short real example, and
`tests/hooks/new_harness_test.sh` walks through the steps.

Anything that can run a shell command can also show up on the bar by
setting the pane options itself:

```sh
tmux set-option -p -t "$TMUX_PANE" @agent_schema 1 \; \
  set-option -p -t "$TMUX_PANE" @agent_app build \; \
  set-option -p -t "$TMUX_PANE" @agent_state running \; \
  set-option -p -t "$TMUX_PANE" @agent_updated "$(date +%s)"
```

[SCHEMA.md](SCHEMA.md) has the details.

## Contributing

Most of this code was written with an LLM, with me guiding and reviewing
it. Pull requests are welcome as long as they are reasonable and serve a
purpose. Excessive, pedantic LLM pull requests will be closed without
hesitation or prejudice.

To run the tests:

```sh
bash tests/run.sh
```

Passing tests print nothing.

## License

MIT. See [LICENSE](LICENSE).
