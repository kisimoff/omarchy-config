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
          )
        | .address
      ' | head -n1
    )"

    if [[ -n "${ADDR}" && "${ADDR}" != "null" ]]; then
      hyprctl dispatch movetoworkspacesilent "${WS},address:${ADDR}" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.1
  done
}

# --- Your session layout ---

# WS 1: Brave
spawn_to_ws 1 'Brave|brave' -- brave --new-window about:blank
sleep 0.1

# WS 2: VS Code (fresh window + isolated profile to avoid instance reuse)
# If Flatpak: replace 'code' with 'flatpak run com.visualstudio.code'
spawn_to_ws 2 'code|Code|codium|VSCodium|code-oss|com\.visualstudio\.code' -- \
  env ELECTRON_OZONE_PLATFORM_HINT=wayland \
  code -n --user-data-dir="$HOME/.cache/omarchy/code-ws2"
sleep 0.1

# WS 6: Alacritty x2 (fastfetch + btop)
spawn_to_ws 6 'Alacritty' -- alacritty -t fastfetch -e fastfetch
sleep 0.05
spawn_to_ws 6 'Alacritty' -- alacritty -t btop -e btop
sleep 0.1

# WS 7: Spotify + EasyEffects (swap to Flatpak IDs if applicable)
spawn_to_ws 7 'Spotify|com\.spotify\.Client' -- spotify
sleep 0.1
spawn_to_ws 7 'EasyEffects|com\.github\.wwmm\.easyeffects' -- easyeffects
sleep 0.1

# WS 8: Brave (second window)
spawn_to_ws 8 'Brave|brave' -- brave --new-window about:blank
