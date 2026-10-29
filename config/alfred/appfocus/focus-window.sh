#!/bin/zsh

set -u

readonly profile_bin="/etc/profiles/per-user/$USER/bin"
readonly yabai_bin="$profile_bin/yabai"
readonly jq_bin="$profile_bin/jq"
readonly bundle_id="${1:-}"

if [[ -z "$bundle_id" ]]; then
  exit 2
fi

# Succeed only when the window actually has focus afterwards. A property query
# keeps the check to one yabai call without starting jq.
focus_window() {
  $yabai_bin -m window --focus "$1" >/dev/null 2>&1 || return
  [[ "$($yabai_bin -m query --windows has-focus --window "$1" 2>/dev/null)" == *'"has-focus":true'* ]]
}

# list-windows.sh passes the app's best window as item variables. Focusing it
# directly skips a second LaunchServices and yabai lookup. Alfred may serve the
# list from its cache, so a window that has since closed or changed falls
# through to the full lookup below.
if [[ "${best_window_id:-}" == <-> ]]; then
  if [[ "${best_window_minimized:-}" == "true" ]]; then
    $yabai_bin -m window "$best_window_id" --deminimize >/dev/null 2>&1 || true
  fi
  focus_window "$best_window_id" && exit 0
fi

# A bundle id is already a valid lsappinfo application specifier, so avoid a
# separate `find` process before reading the pid.
pid_output="$(/usr/bin/lsappinfo info -only pid "$bundle_id" 2>/dev/null)"
app_pid="${pid_output#*=}"
app_pid="${app_pid//[^0-9]/}"

if [[ ! "$app_pid" =~ '^[0-9]+$' ]]; then
  /usr/bin/open -b "$bundle_id" >/dev/null 2>&1
  exit $?
fi

if ! windows_json="$($yabai_bin -m query --windows 2>/dev/null)"; then
  /usr/bin/open -b "$bundle_id" >/dev/null 2>&1
  exit $?
fi

# Return only the three fields needed below; this avoids repeatedly launching
# jq to unpack the selected window. Keep the ranking in sync with
# list-windows.sh.
window_fields="$(
  print -r -- "$windows_json" | $jq_bin -r --argjson pid "$app_pid" '
    [
      .[]
      | select(.pid == $pid)
      | select(."has-ax-reference" == true)
      | select(.role == "AXWindow")
      | select(.subrole == "AXStandardWindow" or .subrole == "AXDialog")
    ]
    | sort_by(
        if ."has-focus" then 0
        elif (.subrole == "AXStandardWindow" and ."is-visible" and (."is-minimized" | not)) then 1
        elif .subrole == "AXStandardWindow" then 2
        elif (."is-visible" and (."is-minimized" | not)) then 3
        else 4
        end
      )
    | .[0] // null
    | if . == null then empty else [.id, ."is-minimized", .space] | @tsv end
  '
)"

if [[ -z "$window_fields" ]]; then
  /usr/bin/open -b "$bundle_id" >/dev/null 2>&1
  exit $?
fi

window_values=("${(@ps:\t:)window_fields}")
window_id="$window_values[1]"
window_minimized="$window_values[2]"
window_space="$window_values[3]"

if [[ "$window_minimized" == "true" ]]; then
  $yabai_bin -m window "$window_id" --deminimize >/dev/null 2>&1 || true
fi

focus_window "$window_id" && exit 0

$yabai_bin -m space --focus "$window_space" >/dev/null 2>&1 || true
focus_window "$window_id" || /usr/bin/open -b "$bundle_id" >/dev/null 2>&1
