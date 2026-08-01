#!/usr/bin/env bash
# Prints the agent bar's status-format string. Pure formats: the S/W loops
# visit every window in every session; windows containing agent panes render
# ONE dim label, then a leading-separator + glyph per agent pane (each glyph
# clickable via range=user|<pane_id>). Leading separators can never dangle:
# the label always precedes the first one. Windows without agents render
# nothing. This grouping is the row structure a vertical status line would
# use.
#
# Every knob is an @agent_bar_* option (see lib/options.sh); defaults follow
# @agent_bar_theme (ascii | nerdfont). Options are baked at build time.
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/options.sh"

theme="$(bar_option theme ascii)"

case "$theme" in
  nerdfont)
    default_pane_sep='  '   # U+E0B1 thin powerline divider
    default_group_sep='  '  # U+E0B0 filled powerline divider
    ;;
  *)
    default_pane_sep=' │ '
    default_group_sep='   '
    ;;
esac

pane_sep="$(bar_option pane_separator "$default_pane_sep")"
group_sep="$(bar_option group_separator "$default_group_sep")"
label_suffix="$(bar_option label_suffix '')"
session_sep="$(bar_option session_separator '/')"
title_max="$(bar_option title_max 24)"

glyph_running="$(bar_option glyph_running '*')"
glyph_subagent="$(bar_option glyph_subagent_running '**')"
glyph_needs_input="$(bar_option glyph_needs_input '?')"
glyph_done="$(bar_option glyph_done '+')"
glyph_error="$(bar_option glyph_error '!')"
glyph_idle="$(bar_option glyph_idle '·')"

# Style+glyph chain keyed on @agent_state. #[...] blocks pass through format
# expansion untouched and are parsed later by format_draw, so emitting them
# from conditional branches is safe. Style syntax uses spaces, never commas,
# to avoid breaking the surrounding #{?...} alternatives.
state_mark="#{?#{==:#{@agent_state},needs-input},#[fg=yellow bold]${glyph_needs_input},#{?#{==:#{@agent_state},error},#[fg=red bold]${glyph_error},#{?#{==:#{@agent_state},done},#[fg=green]${glyph_done},#{?#{==:#{@agent_state},subagent-running},#[fg=cyan]${glyph_subagent},#{?#{==:#{@agent_state},idle},#[fg=colour243]${glyph_idle},#[fg=cyan]${glyph_running}}}}}}"

# Pane title appended (truncated) when something set one; the default title
# is the hostname — noise. title_max 0 hides titles entirely.
if [ "$title_max" != "0" ]; then
  title_suffix="#{?#{&&:#{pane_title},#{!=:#{pane_title},#{host}}}, #{=${title_max}:pane_title},}"
else
  title_suffix=""
fi

# One glyph per agent pane, each led by the pane separator; any set state
# renders — idle is a live agent waiting (dim). A glyph disappears only when
# the agent exits or the pane dies.
pane_glyph="#{?#{@agent_state},#[fg=colour240]${pane_sep}#[default]#[range=user|#{pane_id}]${state_mark}${title_suffix}#[default]#[norange],}"

# Session prefix only for panes outside the viewing client's session.
session_prefix="#{?#{!=:#{session_name},#{client_session}},#{session_name}${session_sep},}"

# A window renders only if some pane in it has agent state (the inner P
# probe emits a marker per agent pane; non-empty means true). The group
# separator trails each group; the ascii default is a plain gap, so nothing
# visible dangles after the last group.
window_has_agents='#{P:#{?#{@agent_state},x,}}'
window_group="#{?${window_has_agents},#[fg=colour243]${session_prefix}#{window_name}${label_suffix}#[default]#{P:${pane_glyph}}#[fg=colour240]${group_sep}#[default],}"

printf '#{S:#{W:%s}}' "$window_group"
