#!/usr/bin/env bash
set -euo pipefail

# spawn_to_ws <ws> <regex_for_class_or_appid> -- <command...>
spawn_to_ws() {
  local WS="$1"; shift
  local MATCH="$1"; shift
  [[ "$1" == "--" ]] && shift

  # Best-effort inline rule on spawn (forking apps may ignore it — we correct below)
  hyprctl dispatch exec "[workspace ${WS} silent] $*" >/dev/null 2>&1 || true

  # Poll up to ~6s for a matching client, then correct placement silently.
  for _ in {1..60}; do
    ADDR="$(
      hyprctl -j clients | jq -r --arg re "$MATCH" '
        .[]
        | select(
            ((.class?         // "" | tostring) | test($re))
            or ((.initialClass? // "" | tostring) | test($re))
            or ((.app_id?        // "" | tostring) | test($re))
            or ((.title?        // "" | tostring) | test($re))
            or ((.initialTitle? // "" | tostring) | test($re))
          )
        | .address
      ' | head -n1
    )"

    if [[ -n "${ADDR}" && "${ADDR}" != "null" ]]; then
      hyprctl dispatch movetoworkspacesilent "${WS},address:${ADDR}" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.05
  done
}

# --- Your session layout ---

# WS 1: Brave
if ! pgrep -f 'brave .*--new-window about:blank' >/dev/null 2>&1; then
  # WS 1: Brave (general profile, rule-free to keep ad-hoc windows flexible)
  spawn_to_ws 1 'Brave|brave' -- brave --new-window about:blank
  sleep 0.05
fi

# WS 2: VS Code (fresh window + isolated profile to avoid instance reuse)
# If Flatpak: replace 'code' with 'flatpak run com.visualstudio.code'
if ! pgrep -f 'code .*--user-data-dir=/home/vincent/.cache/omarchy/code-ws2' >/dev/null 2>&1; then
  spawn_to_ws 2 'code|Code|codium|VSCodium|code-oss|com\.visualstudio\.code' -- \
    env ELECTRON_OZONE_PLATFORM_HINT=wayland \
    code -n --user-data-dir="$HOME/.cache/omarchy/code-ws2"
  sleep 0.05
fi

# WS 6: Alacritty x2 (fastfetch + btop)
spawn_to_ws 6 'Alacritty|WS6-fastfetch' -- \
  alacritty -t WS6-fastfetch -e bash -lc 'fastfetch; exec bash'
sleep 0.05
spawn_to_ws 6 'Alacritty|WS6-btop' -- \
  alacritty -t WS6-btop -e bash -lc 'btop'
sleep 0.05

# WS 7: Spotify + EasyEffects (swap to Flatpak IDs if applicable)
spawn_to_ws 7 'Spotify|com\.spotify\.Client' -- spotify
sleep 0.05
spawn_to_ws 7 'EasyEffects|com\.github\.wwmm\.easyeffects' -- easyeffects
sleep 0.05

# WS 8: Brave (manual)
spawn_to_ws 8 'Omarchy Manual' -- \
  brave --new-window "https://learn.omacom.io/2/the-omarchy-manual/65/dotfiles"
