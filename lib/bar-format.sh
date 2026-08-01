#!/usr/bin/env bash
# Prints the agent bar's status-format string. Pure formats: the S/W loops
# visit every window in every session; windows containing agent panes render
# ONE dim label followed by a glyph per agent pane (each glyph clickable via
# range=user|<pane_id>). Windows without agents render nothing. This grouping
# is the same row structure a vertical status line would use.
set -u

# Style+glyph chain keyed on @agent_state. #[...] blocks pass through format
# expansion untouched and are parsed later by format_draw, so emitting them
# from conditional branches is safe. Style syntax uses spaces, never commas,
# to avoid breaking the surrounding #{?...} alternatives.
state_mark='#{?#{==:#{@agent_state},needs-input},#[fg=yellow bold]?,#{?#{==:#{@agent_state},error},#[fg=red bold]!,#{?#{==:#{@agent_state},done},#[fg=green]+,#{?#{==:#{@agent_state},subagent-running},#[fg=cyan]**,#{?#{==:#{@agent_state},idle},#[fg=colour243]·,#[fg=cyan]*}}}}}'

# Pane title appended (truncated) when something set one; the default title
# is the hostname — noise.
title_suffix='#{?#{&&:#{pane_title},#{!=:#{pane_title},#{host}}}, #{=24:pane_title},}'

# One glyph per agent pane; any set state renders — idle is a live agent
# waiting (dim). A glyph disappears only when the agent exits or the pane
# dies. Leading space so the closing bracket hugs the last glyph.
pane_glyph="#{?#{@agent_state}, #[range=user|#{pane_id}]${state_mark}${title_suffix}#[default]#[norange],}"

# Session prefix only for panes outside the viewing client's session.
session_prefix='#{?#{!=:#{session_name},#{client_session}},#{session_name}:,}'

# A window renders only if some pane in it has agent state (the inner P
# probe emits a marker per agent pane; non-empty means true). Groups are
# bracketed dim so window separation reads differently from the pane
# spacing inside a group — and nothing dangles after the last group.
window_has_agents='#{P:#{?#{@agent_state},x,}}'
window_group="#{?${window_has_agents},#[fg=colour240][#[fg=colour243]${session_prefix}#{window_name}#[default]#{P:${pane_glyph}}#[fg=colour240]]#[default] ,}"

printf '#{S:#{W:%s}}' "$window_group"
