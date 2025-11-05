#!/usr/bin/env bash
set -euo pipefail

# Log helper for troubleshooting placement issues.
LOG_FILE="$HOME/.cache/omarchy/hypr-startup.log"
mkdir -p "$(dirname "$LOG_FILE")"
: >"$LOG_FILE"
log() {
  printf '%(%Y-%m-%d %H:%M:%S)T %s\n' -1 "$*" >>"$LOG_FILE"
}

# spawn_to_ws <ws> <regex_for_class_or_appid> -- <command...>
spawn_to_ws() {
  local WS="$1"; shift
  local MATCH="$1"; shift
  [[ "$1" == "--" ]] && shift

  mapfile -t BEFORE < <(
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
    '
  )

  local CMD
  printf -v CMD '%q ' "$@"
  CMD="${CMD% }"

  # Best-effort inline rule on spawn (forking apps may ignore it — we correct below)
  log "spawn_to_ws: WS=${WS} cmd=${CMD} before=${BEFORE[*]}"
  hyprctl dispatch exec "[workspace ${WS} silent] ${CMD}" >>"$LOG_FILE" 2>&1 || true

  # Poll up to ~4s for a matching client, prioritising new addresses.
  local moved=false
  for _ in {1..200}; do
    mapfile -t CURRENT < <(
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
      '
    )

    local ADDR=""
    if ((${#CURRENT[@]})); then
      for candidate in "${CURRENT[@]}"; do
        local seen=false
        for old in "${BEFORE[@]}"; do
          if [[ "$candidate" == "$old" ]]; then
            seen=true
            break
          fi
        done
        if ! $seen; then
          ADDR="$candidate"
          break
        fi
      done

      if [[ -z "$ADDR" && ${#BEFORE[@]} -eq 0 ]]; then
        ADDR="${CURRENT[0]}"
      fi
    fi

    if [[ -n "$ADDR" && "$ADDR" != "null" ]]; then
      log "spawn_to_ws: moving ${ADDR} to WS ${WS}"
      hyprctl dispatch movetoworkspacesilent "${WS},address:${ADDR}" >>"$LOG_FILE" 2>&1 || true
      moved=true
      break
    fi
    sleep 0.02
  done

  if ! $moved; then
    log "spawn_to_ws: timeout waiting for match ${MATCH} on WS ${WS}"
  fi
}

# --- Your session layout ---

# WS 1: Brave
if ! pgrep -f 'brave .*--new-window about:blank' >/dev/null 2>&1; then
  # WS 1: Brave (general profile, rule-free to keep ad-hoc windows flexible)
  spawn_to_ws 1 'Brave|brave' -- brave --new-window about:blank
  sleep 0.02
fi

# WS 2: VS Code (fresh window + isolated profile to avoid instance reuse)
# If Flatpak: replace 'code' with 'flatpak run com.visualstudio.code'
if ! pgrep -f 'code .*--user-data-dir=/home/vincent/.cache/omarchy/code-ws2' >/dev/null 2>&1; then
  spawn_to_ws 2 'code|Code|codium|VSCodium|code-oss|com\.visualstudio\.code' -- \
    env ELECTRON_OZONE_PLATFORM_HINT=wayland \
    code -n --user-data-dir="$HOME/.cache/omarchy/code-ws2"
  sleep 0.02
fi

# WS 5: PWAs (Messenger, WhatsApp, Instagram)
if ! pgrep -f '--app=https://www.facebook.com/messages/e2ee/t/9709072432525309' >/dev/null 2>&1; then
  spawn_to_ws 5 'Brave|brave' -- \
    omarchy-launch-webapp https://www.facebook.com/messages/e2ee/t/9709072432525309
  sleep 0.02
fi
if ! pgrep -f '--app=https://web.whatsapp.com/' >/dev/null 2>&1; then
  spawn_to_ws 5 'Brave|brave' -- \
    omarchy-launch-webapp https://web.whatsapp.com/
  sleep 0.02
fi
if ! pgrep -f '--app=https://www.instagram.com/direct/inbox/' >/dev/null 2>&1; then
  spawn_to_ws 5 'Brave|brave' -- \
    omarchy-launch-webapp https://www.instagram.com/direct/inbox/
  sleep 0.02
fi

# WS 6: Alacritty x2 (fastfetch + btop)
spawn_to_ws 6 'WS6-fastfetch' -- \
  alacritty -t WS6-fastfetch -e bash -lc 'fastfetch; exec bash'
sleep 0.02
spawn_to_ws 6 'WS6-btop' -- \
  alacritty -t WS6-btop -e bash -lc 'btop'
sleep 0.02

# WS 7: Spotify + EasyEffects (swap to Flatpak IDs if applicable)
spawn_to_ws 7 'Spotify|com\.spotify\.Client' -- spotify
sleep 0.02
spawn_to_ws 7 'EasyEffects|com\.github\.wwmm\.easyeffects' -- easyeffects
sleep 0.02

# WS 8: Brave (manual)
spawn_to_ws 8 'Brave|brave' -- \
  brave --new-window "http://localhost:3000"

# Ensure monitor workspaces settle: HDMI-A-1 on ws6, DP-1 on ws1
hyprctl dispatch focusmonitor HDMI-A-1 >/dev/null 2>&1 || true
hyprctl dispatch workspace 8 >/dev/null 2>&1 || true
sleep 0.02
hyprctl dispatch splitratio 0.66 >/dev/null 2>&1 || true
hyprctl dispatch workspace 6 >/dev/null 2>&1 || true
hyprctl dispatch focusmonitor DP-1 >/dev/null 2>&1 || true
hyprctl dispatch workspace 1 >/dev/null 2>&1 || true

log "startup complete"
