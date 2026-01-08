#!/usr/bin/env bash
set -euo pipefail

# Note: This file is currently disabled in favor of startup.sh
# To re-enable, add 'exec-once = ~/.config/hypr/autostart.sh' to hyprland.conf

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

# --- Legacy session layout ---

# WS 1: Brave
spawn_to_ws 1 'Brave|brave' -- brave --new-window about:blank
sleep 0.1

# WS 6: Alacritty x2 (fastfetch + btop) + Spotify
spawn_to_ws 6 'Alacritty' -- alacritty -t btop -e btop
sleep 0.05
spawn_to_ws 6 'Spotify|com\.spotify\.Client' -- spotify
sleep 0.1

# EasyEffects (Service Mode)
easyeffects --service-mode &

# WS 7: Brave (second window)
spawn_to_ws 7 'Brave|brave' -- brave --new-window about:blank
