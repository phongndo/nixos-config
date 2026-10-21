#!/bin/zsh

set -eu

readonly profile_bin="/etc/profiles/per-user/$USER/bin"
readonly yabai_bin="$profile_bin/yabai"
readonly jq_bin="$profile_bin/jq"

# Window data enriches subtitles and searching, but the app list remains useful
# when yabai is unavailable or an app currently has no standard window. Query
# yabai while LaunchServices is read below; the final jq reads it from fd 3.
exec 3< <($yabai_bin -m query --windows 2>/dev/null || print -r -- '[]')

if ! visible_asns="$(/usr/bin/lsappinfo -nonames visibleProcessList 2>/dev/null)"; then
  $jq_bin -cn '{items: [{title: "Unable to query running apps", subtitle: "LaunchServices did not respond", valid: false}]}'
  exit 0
fi

# Ask LaunchServices for every app in one process. Spawning one lsappinfo per
# app was the largest part of the Script Filter's cold-start latency.
app_asns=( ${=visible_asns} )
info_args=()
for app_asn in "${app_asns[@]}"; do
  info_args+=(info -only pid bundleID bundlepath displayname "$app_asn")
done

if (( ${#info_args[@]} == 0 )); then
  app_info=""
elif ! app_info="$(/usr/bin/lsappinfo -nonames "${info_args[@]}" 2>/dev/null)"; then
  $jq_bin -cn '{items: [{title: "Unable to read running apps", subtitle: "LaunchServices did not respond", valid: false}]}'
  exit 0
fi

app_records=()
app_pid=""
bundle_id=""
app_path=""
app_name=""

append_app_record() {
  [[ -n "$app_name" && -n "$bundle_id" && "$app_pid" == <-> ]] || return 0
  [[ "$app_path" == *.app && -d "$app_path" ]] || return 0
  app_records+=("$app_pid"$'\t'"$app_name"$'\t'"$bundle_id"$'\t'"$app_path")
}

# `info -only` emits one key per line and starts each app with its pid.
while IFS= read -r line; do
  case "$line" in
    '"pid"='*)
      append_app_record
      app_pid="${line#*=}"
      bundle_id=""
      app_path=""
      app_name=""
      ;;
    '"CFBundleIdentifier"="'*)
      bundle_id="${line#\"CFBundleIdentifier\"=\"}"
      bundle_id="${bundle_id%\"}"
      ;;
    '"LSBundlePath"="'*)
      app_path="${line#\"LSBundlePath\"=\"}"
      app_path="${app_path%\"}"
      ;;
    '"LSDisplayName"="'*)
      app_name="${line#\"LSDisplayName\"=\"}"
      app_name="${app_name%\"}"
      ;;
  esac
done <<< "$app_info"
append_app_record

apps_tsv="$(printf '%s\n' "${app_records[@]}")"

$jq_bin -c --arg apps_tsv "$apps_tsv" '
  . as $windows
  | ($apps_tsv
   | split("\n")
   | map(select(length > 0) | split("\t"))
   | map(select(length >= 4) | {
       pid: (.[0] | tonumber),
       name: .[1],
       bundle_id: .[2],
       path: .[3]
     })) as $apps
  | {
    # Alfred serves this list immediately on later invocations, then refreshes
    # stale results in the background. Five seconds is its minimum cache TTL.
    cache: {seconds: 5, loosereload: true},
    items: [
      $apps[]
      | . as $app
      | ([$windows[]
          | select(.pid == $app.pid)
          | select(."has-ax-reference" == true)
          | select(.role == "AXWindow")
          | select(.subrole == "AXStandardWindow" or .subrole == "AXDialog")
        ]) as $app_windows
      # Keep this ranking in sync with focus-window.sh, which receives the
      # chosen window and falls back to the same choice.
      | ($app_windows
         | sort_by(
             if ."has-focus" then 0
             elif (.subrole == "AXStandardWindow" and ."is-visible" and (."is-minimized" | not)) then 1
             elif .subrole == "AXStandardWindow" then 2
             elif (."is-visible" and (."is-minimized" | not)) then 3
             else 4
             end
           )
         | .[0] // null) as $window
      | {
          title: $app.name,
          subtitle: (
            if $window == null then $app.path
            else
              (if ($window.title | length) > 0 then $window.title else "Untitled window" end)
              + "  ·  Space " + ($window.space | tostring)
              + (if ($app_windows | length) > 1
                 then "  ·  " + (($app_windows | length) | tostring) + " windows"
                 else ""
                 end)
              + (if $window."is-minimized" then "  ·  Minimized"
                 elif $window."is-hidden" then "  ·  Hidden"
                 elif $window."is-floating" then "  ·  Floating"
                 else ""
                 end)
            end
          ),
          arg: $app.bundle_id,
          match: ($app.name + " " + ($app_windows | map(.title) | join(" "))),
          autocomplete: $app.name,
          valid: true,
          icon: {type: "fileicon", path: $app.path}
        }
        + (if $window == null then {}
           else {variables: {
             best_window_id: ($window.id | tostring),
             best_window_minimized: ($window."is-minimized" | tostring)
           }}
           end)
    ]
    # No item UID: Alfred must preserve this exact alphabetical order instead
    # of applying its learned, recently-used ranking.
    | sort_by(.title | ascii_downcase)
  }
' <&3
