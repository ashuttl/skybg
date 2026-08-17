#!/bin/bash
set -euo pipefail

if (( EUID == 0 )); then
  echo "skybg: install as your regular user, not root" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR=${HOME}/.local/bin
UNIT_DIR=${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user

missing=()
for command in omarchy python3 magick montage systemctl; do
  command -v "$command" >/dev/null || missing+=("$command")
done
if ((${#missing[@]})); then
  echo "skybg: missing required commands: ${missing[*]}" >&2
  echo "On Omarchy, ImageMagick can be installed with: omarchy pkg add imagemagick" >&2
  exit 1
fi

mkdir -p "$BIN_DIR" "$UNIT_DIR"

backup_if_changed() {
  local source=$1 destination=$2
  if [[ -e $destination ]] && ! cmp -s "$source" "$destination"; then
    local backup="${destination}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a -- "$destination" "$backup"
    echo "Backed up modified $destination to $backup"
  fi
}

backup_if_changed "$ROOT/bin/skybg" "$BIN_DIR/skybg"
backup_if_changed "$ROOT/systemd/skybg.service" "$UNIT_DIR/skybg.service"
backup_if_changed "$ROOT/systemd/skybg.timer" "$UNIT_DIR/skybg.timer"
# Omarchy's hook command intentionally uses ~/.config/omarchy, independent of
# XDG_CONFIG_HOME.
HOOK=${HOME}/.config/omarchy/hooks/theme-set.d/skybg-retint
backup_if_changed "$ROOT/hooks/skybg-retint" "$HOOK"

install -m 755 "$ROOT/bin/skybg" "$BIN_DIR/skybg"
install -m 644 "$ROOT/systemd/skybg.service" "$UNIT_DIR/skybg.service"
install -m 644 "$ROOT/systemd/skybg.timer" "$UNIT_DIR/skybg.timer"
omarchy hook install theme-set "$ROOT/hooks/skybg-retint"
systemctl --user daemon-reload

echo
echo "Installed skybg for ${USER}. The timer was not started."
echo "Next:"
echo "  skybg config location LAT LON   # or configure linecast"
echo "  skybg doctor"
echo "  skybg preview"
echo "  skybg on"
