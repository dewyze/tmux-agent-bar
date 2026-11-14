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
position="${AGENT_BAR_FORCE_POSITION:-$(bar_option position left)}"
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
  # Hierarchy indent: with one session on the bar, its windows sit flat
  # and their panes at 2 spaces. With several, every session has a header
  # row, its windows indent 2 under it and their panes 4.
  # @agent_bar_windows agents (the default) lists only windows with an
  # agent, and only foreign sessions with one; when there is none the bar
  # says so, or it would look switched off. `all` lists every window and
  # session, a navigation surface that never reflows. Either way only
  # agent panes get badge rows.
  # Overflow: the whole tree is a tmux list (list=on) with "more above" and
  # "more below" marker rows, upstream's ACS arrows. The current window's
  # label row is the list focus, so when the tree is taller than the bar
  # tmux scrolls to keep it visible. Local windows only: a foreign
  # session's active window must not take the focus.
  v_list="#[list=on]#[list=left-marker]#[acs]-#[noacs]#[nl]#[list=right-marker]#[acs].#[noacs]#[nl]"
  v_focus='#{?window_active,#[list=focus],}'
  v_badge() { printf '#{?#{@agent_state},%s#[range=user|#{pane_id}]%s%s#[default]#[norange]#[nl],}' "$1" "${state_mark}" "${name_suffix}"; }
  # @agent_bar_padding spaces either side of a window name, inside its
  # style and click range, so a name with a background reads as a block.
  v_pad="$(bar_option padding 1)"
  [[ "$v_pad" =~ ^[0-9]+$ ]] || v_pad=1
  v_pad="$(printf "%${v_pad}s" '')"
  v_window() { printf '%s%s%s#[range=user|#{window_id}]%s#{window_name}%s%s#[norange]#[default]#[list=on]#[nl]#{P:%s}' "$1" "$3" "${wstyle}" "${v_pad}" "${label_suffix}" "${v_pad}" "$(v_badge "$2")"; }
  # A session's rows under its header: windows indent 2, their panes 4.
  # $1: extra style for the header's name, $2: per-window prefix (the list
  # focus, for the viewing session).
  v_header() { printf '#[fg=%s bold]%s#[default]#[fg=%s%s]#[range=user|#{session_id}]#{session_name}#[norange]#[default]#[nl]' "$accent" "$session_marker" "$accent" "$1"; }
  v_flat_row="$(v_window '' '  ' "$v_focus")"
  v_local_row="$(v_window '  ' '    ' "$v_focus")"
  v_foreign_row="$(v_window '  ' '    ' '')"
  v_empty=""
  if [ "$(bar_option windows agents)" = "all" ]; then
    # Headers appear once a second session exists.
    several='#{>:#{server_sessions},1}'
    v_local="$(v_header ' bold')#{W:${v_local_row}}"
    v_foreign="$(v_header '')#{W:${v_foreign_row}}"
  else
    window_has_agents='#{P:#{?#{@agent_state},x,}}'
    # Headers appear once another session has an agent to list.
    several="#{S:#{?${is_local},,${session_has_agents}}}"
    v_flat_row="#{?${window_has_agents},${v_flat_row},}"
    v_local="#{?${session_has_agents},$(v_header ' bold')#{W:#{?${window_has_agents},${v_local_row},}},}"
    v_foreign="#{?${session_has_agents},$(v_header '')#{W:#{?${window_has_agents},${v_foreign_row},}},}"
    # The note looks where the bar looks: this session, or every session.
    if [ "$mode" = "off" ]; then
      any_agents="$session_has_agents"
    else
      any_agents="#{S:${session_has_agents}}"
    fi
    v_empty="#{?${any_agents},,#[fg=colour243]no agents#[default]#[nl]}"
  fi
  # With one session on the bar its windows sit flat, with no header. With
  # several, every session gets one, the viewing session's in bold.
  if [ "$mode" = "off" ]; then
    printf '%s%s#{S:#{?%s,#{W:%s},}}' "$v_list" "$v_empty" "$is_local" "$v_flat_row"
  else
    printf '%s%s#{S:#{?%s,#{?%s,%s,#{W:%s}},%s}}' "$v_list" "$v_empty" "$is_local" "$several" "$v_local" "$v_flat_row" "$v_foreign"
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
