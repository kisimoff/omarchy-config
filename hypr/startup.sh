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
  spawn_to_ws 1 'Brave|brave' -- brave --new-window about:blank
fi

# WS 2: Antigravity (Development)
# Replaced VSCode with Antigravity
if ! pgrep -f 'antigravity' >/dev/null 2>&1; then
  log "Spawning Antigravity to WS 2"
  spawn_to_ws 2 'antigravity' -- antigravity
fi

# WS 9: Messaging (Messenger, WhatsApp, Instagram, Discord)
# Check for native discord first, otherwise use webapp
if ! pgrep -x "discord" >/dev/null 2>&1; then
    if command -v discord >/dev/null 2>&1; then
        log "Spawning native Discord to WS 9"
        spawn_to_ws 9 'discord' -- discord
    fi
fi

MESSAGING_URLS=(
  "https://www.facebook.com/messages/e2ee/t/9709072432525309"
  "https://web.whatsapp.com/"
  "https://www.instagram.com/direct/inbox/"
)

# Only launch webapp Discord if native isn't running
if ! pgrep -f "discord" >/dev/null 2>&1; then
    MESSAGING_URLS+=("https://discord.com/channels/@me")
fi

for url in "${MESSAGING_URLS[@]}"; do
  if ! pgrep -f "--app=$url" >/dev/null 2>&1; then
    log "Spawning webapp $url to WS 9"
    spawn_to_ws 9 'Brave|brave' -- omarchy-launch-webapp "$url"
    sleep 0.1
  fi
done

# WS 6: System Utilities & Music
if ! pgrep -f 'WS6-btop' >/dev/null 2>&1; then
    spawn_to_ws 6 'WS6-btop' -- alacritty -t WS6-btop -e bash -lc 'btop'
fi

if ! pgrep -x "spotify" >/dev/null 2>&1; then
    spawn_to_ws 6 'Spotify|com\.spotify\.Client' -- spotify
fi

# EasyEffects (Service Mode - No GUI)
if ! pgrep -x "easyeffects" >/dev/null 2>&1; then
  easyeffects --service-mode &
fi

# WS 7: Localhost Dev
if ! pgrep -f "localhost:3000" >/dev/null 2>&1; then
    spawn_to_ws 7 'Brave|brave' -- brave --new-window "http://localhost:3000"
fi

# Final Cleanup: Settle monitors
log "Settling monitors and workspaces..."
hyprctl dispatch focusmonitor HDMI-A-1 >/dev/null 2>&1 || true
hyprctl dispatch workspace 9 >/dev/null 2>&1 || true # Focus messaging
sleep 0.1
hyprctl dispatch focusmonitor DP-1 >/dev/null 2>&1 || true
hyprctl dispatch workspace 1 >/dev/null 2>&1 || true # Focus main browser

log "startup complete"
