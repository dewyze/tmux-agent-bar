#!/usr/bin/env bash
# Prints the agent bar's status-format string(s). Pure formats: S/W/P loops
# visit every pane; windows with agent panes render ONE bare label plus a
# leading-separator + glyph per agent pane (clickable via range=user).
# Sessions are the top grouping rank: foreign sessions (relative to the
# viewing client) are introduced by an accent marker + session name once.
#
# Argument: none -> the primary line; "foreign" -> the secondary line used
# by cross_session=line mode (compact: marker + session name + bare glyphs).
#
# @agent_bar_cross_session: inline (default) — foreign sessions share the
# primary line; line — primary is local-only, foreign renders on its own
# line; off — foreign agents are not rendered at all.
#
# Every knob is an @agent_bar_* option (see lib/options.sh), baked at build
# time. Session order is tmux index order (formats cannot sort).
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/options.sh"

part="${1:-}"
theme="$(bar_option theme ascii)"
position="${AGENT_BAR_FORCE_POSITION:-$(bar_option position status)}"
mode="$(bar_option cross_session inline)"

# Separator hierarchy, all visible characters — spaces are not separators:
# session marker (accent) > group opener > pane divider. Pane and group
# separators LEAD what they introduce, so nothing ever dangles.
# Powerline glyphs are built from bytes, never source literals: they are
# private-use-area characters that editors and tooling silently drop (this
# file once shipped with them replaced by spaces, and a test asserting a
# vanished literal passed vacuously).
powerline_thin="$(printf '\xee\x82\xb1')"    # U+E0B1
powerline_filled="$(printf '\xee\x82\xb0')"  # U+E0B0

case "$theme" in
  nerdfont)
    default_pane_sep=" ${powerline_thin} "
    default_group_sep=" ${powerline_filled} "
    default_session_marker=" ${powerline_filled} "
    ;;
  *)
    default_pane_sep=' │ '
    default_group_sep=' ║ '
    default_session_marker=' ▌ '
    ;;
esac

pane_sep="$(bar_option pane_separator "$default_pane_sep")"
group_sep="$(bar_option group_separator "$default_group_sep")"
session_marker="$(bar_option session_marker "$default_session_marker")"
label_suffix="$(bar_option label_suffix '')"
name_max="$(bar_option name_max 24)"
accent="$(bar_option accent colour109)"

# Window-group styles (space-separated style syntax — commas would split
# the surrounding conditionals). scripts/adopt-theme.sh infers these from
# the user's existing status line; defaults are theme-neutral placeholders
# until the colours pass.
style_window="$(bar_option style_window 'fg=colour243')"
style_window_active="$(bar_option style_window_active 'fg=colour250 bold')"
status_bg="$(bar_option status_bg '')"

# Segment mode: nerdfont theme + both window styles carrying backgrounds +
# a known status background. Groups render as true powerline segments with
# transition chevrons (old bg over new bg) at both edges. Thin dividers
# default to a contrasting fg there — colour240 vanishes against gray
# segment backgrounds.
bg_of() { case "$1" in *bg=*) v="${1##*bg=}"; printf '%s' "${v%% *}" ;; esac; }
bg_active="$(bg_of "$style_window_active")"
bg_inactive="$(bg_of "$style_window")"
segments=0
if [ "$theme" = nerdfont ] && [ -n "$status_bg" ] && [ -n "$bg_active" ] && [ -n "$bg_inactive" ]; then
  segments=1
fi
if [ "$segments" = 1 ]; then
  divider_fg="$(bar_option divider_fg 'colour245')"
else
  divider_fg="$(bar_option divider_fg 'colour240')"
fi

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

# Badge text after the glyph, strict precedence (SCHEMA.md): our rename
# (@agent_name) -> the harness (@agent_app) -> nothing. Pane titles and
# commands never render. Truncated at name_max.
name_suffix="#{?#{@agent_name}, #{=${name_max}:@agent_name},#{?#{@agent_app}, #{@agent_app},}}"

# One glyph per agent pane, each led by the pane separator; any set state
# renders — idle is a live agent waiting (dim). A glyph disappears only when
# the agent exits or the pane dies. The compact variant (foreign line)
# drops names.
# Inside a styled group, glyphs restore the group style (not #[default])
# after each badge so a group background survives the whole run; separators
# change only fg, so the background persists across them too.
wstyle="#{?window_active,#[${style_window_active}],#[${style_window}]}"
grouped_glyph="#{?#{@agent_state},#[fg=${divider_fg}]${pane_sep}#[range=user|#{pane_id}]${state_mark}${name_suffix}#[nobold]${wstyle}#[norange],}"
compact_glyph="#{?#{@agent_state},#[fg=${divider_fg}]${pane_sep}#[default]#[range=user|#{pane_id}]${state_mark}#[default]#[norange],}"

# A window renders only if some pane in it has agent state; labels are
# always bare — session identity lives at the session rank, not repeated
# per window.
window_has_agents='#{P:#{?#{@agent_state},x,}}'
if [ "$segments" = 1 ]; then
  seg_in="#{?window_active,#[fg=${status_bg} bg=${bg_active}],#[fg=${status_bg} bg=${bg_inactive}]}${powerline_filled}"
  seg_out="#{?window_active,#[fg=${bg_active} bg=${status_bg}],#[fg=${bg_inactive} bg=${status_bg}]}${powerline_filled}#[default]"
  window_group="#{?${window_has_agents}, ${seg_in}${wstyle} #[range=user|#{window_id}]#{window_name}${label_suffix}#[norange]#{P:${grouped_glyph}} ${seg_out},}"
else
  window_group="#{?${window_has_agents},#[fg=${divider_fg}]${group_sep}#[default]${wstyle}#[range=user|#{window_id}]#{window_name}${label_suffix}#[norange]#{P:${grouped_glyph}}#[default],}"
fi
windows="#{W:${window_group}}"

session_has_agents='#{W:#{P:#{?#{@agent_state},x,}}}'
is_local='#{==:#{session_name},#{client_session}}'

# Foreign session intro: accent marker + name once. Accent colour is a
# placeholder until the colours pass.
session_intro="#[fg=${accent} bold]${session_marker}#[default]#[fg=${accent}]#[range=user|#{session_id}]#{session_name}#[norange]#[default]"
inline_foreign="#{?${session_has_agents},${session_intro}${windows},}"
compact_foreign="#{?${session_has_agents},${session_intro}#{W:#{P:${compact_glyph}}},}"

# Vertical layout (@agent_bar_position left/right, tmux side-status): same
# badge vocabulary, rows joined by #[nl] — window label row, indented pane
# rows, an accent header row per foreign session. No horizontal separators
# or segments; the side bar has its own affordances.
if [ "$position" != "status" ]; then
  # Hierarchy indent: local windows sit flat (no header above them), their
  # panes at 2 spaces; foreign windows indent 2 under their session header,
  # their panes 4.
  # The tree is unconditional: every window (and every foreign session
  # header) gets a row, so the bar is a navigation surface even with zero
  # agents and nothing reflows when the first one appears. Only the pane
  # badge rows are gated on agent state.
  v_badge() { printf '#{?#{@agent_state},%s#[range=user|#{pane_id}]%s%s#[default]#[norange]#[nl],}' "$1" "${state_mark}" "${name_suffix}"; }
  v_window() { printf '%s%s#[range=user|#{window_id}]#{window_name}%s#[norange]#[default]#[nl]#{P:%s}' "$1" "${wstyle}" "${label_suffix}" "$(v_badge "$2")"; }
  v_windows_local="#{W:$(v_window '' '  ')}"
  v_windows_foreign="#{W:$(v_window '  ' '    ')}"
  v_header="#[fg=${accent} bold]${session_marker}#[default]#[fg=${accent}]#[range=user|#{session_id}]#{session_name}#[norange]#[default]#[nl]"
  v_foreign="${v_header}${v_windows_foreign}"
  if [ "$mode" = "off" ]; then
    printf '#{S:#{?%s,%s,}}' "$is_local" "$v_windows_local"
  else
    printf '#{S:#{?%s,%s,%s}}' "$is_local" "$v_windows_local" "$v_foreign"
  fi
  exit 0
fi

if [ "$part" = "foreign" ]; then
  printf '#{S:#{?%s,,%s}}' "$is_local" "$compact_foreign"
  exit 0
fi

case "$mode" in
  inline) printf '#{S:#{?%s,%s,%s}}' "$is_local" "$windows" "$inline_foreign" ;;
  *)      printf '#{S:#{?%s,%s,}}' "$is_local" "$windows" ;;
esac
