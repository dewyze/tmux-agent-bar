#!/usr/bin/env bash
# Prints the agent bar's status-format string. Pure formats: the S/W/P loops
# visit every pane in every session; panes with a non-idle @agent_state render
# one clickable badge (range=user|<pane_id>) with a per-state style and glyph.
set -u

# Style+glyph chain keyed on @agent_state. #[...] blocks pass through format
# expansion untouched and are parsed later by format_draw, so emitting them
# from conditional branches is safe. Style syntax uses spaces, never commas,
# to avoid breaking the surrounding #{?...} alternatives.
state_mark='#{?#{==:#{@agent_state},needs-input},#[fg=yellow bold]?,#{?#{==:#{@agent_state},error},#[fg=red bold]!,#{?#{==:#{@agent_state},done},#[fg=green]+,#{?#{==:#{@agent_state},subagent-running},#[fg=cyan]**,#[fg=cyan]*}}}}'

badge="#[range=user|#{pane_id}]${state_mark} #{session_name}:#{window_name}#[default]#[norange]  "

visible="#{?#{&&:#{@agent_state},#{!=:#{@agent_state},idle}},${badge},}"

printf '#{S:#{W:#{P:%s}}}' "$visible"
