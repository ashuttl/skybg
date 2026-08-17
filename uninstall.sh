#!/bin/bash
set -euo pipefail

if (( EUID == 0 )); then
  echo "skybg: uninstall as your regular user, not root" >&2
  exit 1
fi

BIN=${HOME}/.local/bin/skybg
UNIT_DIR=${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user
HOOK=${HOME}/.config/omarchy/hooks/theme-set.d/skybg-retint
PLIST=${HOME}/Library/LaunchAgents/com.skybg.tick.plist
CONFIG_DIR=${XDG_CONFIG_HOME:-${HOME}/.config}/skybg
STATE_DIR=${XDG_STATE_HOME:-${HOME}/.local/state}/skybg

if [[ $(uname -s) == Darwin ]]; then
  launchctl bootout "gui/$(id -u)/com.skybg.tick" 2>/dev/null || true
  paths=("$BIN" "$PLIST")
else
  systemctl --user disable --now skybg.timer 2>/dev/null || true
  paths=("$BIN" "$UNIT_DIR/skybg.service" "$UNIT_DIR/skybg.timer" "$HOOK")
fi

for path in "${paths[@]}"; do
  if [[ -e $path || -L $path ]]; then
    rm -- "$path"
    echo "Removed $path"
  fi
done
if [[ $(uname -s) != Darwin ]]; then
  systemctl --user daemon-reload
fi

if [[ ${1:-} == "--purge" ]]; then
  rm -rf -- "$CONFIG_DIR" "$STATE_DIR"
  echo "Removed skybg configuration and generated state"
else
  echo "Kept configuration and generated state. Use ./uninstall.sh --purge to remove them."
fi
echo "The current background was left unchanged."
