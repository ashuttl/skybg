#!/bin/bash
set -euo pipefail

if (( EUID == 0 )); then
  echo "skybg: install as your regular user, not root" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR=${HOME}/.local/bin
UNIT_DIR=${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user
PLATFORM=$(uname -s)

if [[ $PLATFORM == Darwin ]]; then
  required=(python3 magick montage)
else
  required=(omarchy python3 magick montage systemctl)
fi
missing=()
for command in "${required[@]}"; do
  command -v "$command" >/dev/null || missing+=("$command")
done
if ((${#missing[@]})); then
  echo "skybg: missing required commands: ${missing[*]}" >&2
  if [[ $PLATFORM == Darwin ]]; then
    echo "On macOS, ImageMagick can be installed with: brew install imagemagick" >&2
  else
    echo "On Omarchy, ImageMagick can be installed with: omarchy pkg add imagemagick" >&2
  fi
  exit 1
fi

backup_if_changed() {
  local source=$1 destination=$2
  if [[ -e $destination ]] && ! cmp -s "$source" "$destination"; then
    local backup="${destination}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a -- "$destination" "$backup"
    echo "Backed up modified $destination to $backup"
  fi
}

mkdir -p "$BIN_DIR"
backup_if_changed "$ROOT/bin/skybg" "$BIN_DIR/skybg"
install -m 755 "$ROOT/bin/skybg" "$BIN_DIR/skybg"

if [[ $PLATFORM == Darwin ]]; then
  AGENT_DIR=${HOME}/Library/LaunchAgents
  PLIST=$AGENT_DIR/com.skybg.tick.plist
  mkdir -p "$AGENT_DIR"
  STAGED=$(mktemp)
  cat > "$STAGED" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.skybg.tick</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BIN_DIR}/skybg</string>
    <string>tick</string>
  </array>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
PLIST
  backup_if_changed "$STAGED" "$PLIST"
  install -m 644 "$STAGED" "$PLIST"
  rm -f -- "$STAGED"
else
  mkdir -p "$UNIT_DIR"
  backup_if_changed "$ROOT/systemd/skybg.service" "$UNIT_DIR/skybg.service"
  backup_if_changed "$ROOT/systemd/skybg.timer" "$UNIT_DIR/skybg.timer"
  # Omarchy's hook command intentionally uses ~/.config/omarchy, independent of
  # XDG_CONFIG_HOME.
  HOOK=${HOME}/.config/omarchy/hooks/theme-set.d/skybg-retint
  backup_if_changed "$ROOT/hooks/skybg-retint" "$HOOK"

  install -m 644 "$ROOT/systemd/skybg.service" "$UNIT_DIR/skybg.service"
  install -m 644 "$ROOT/systemd/skybg.timer" "$UNIT_DIR/skybg.timer"
  omarchy hook install theme-set "$ROOT/hooks/skybg-retint"
  systemctl --user daemon-reload
fi

echo
echo "Installed skybg for ${USER}. The timer was not started."
echo "Next:"
echo "  skybg config location LAT LON   # or configure linecast"
echo "  skybg doctor"
echo "  skybg preview"
echo "  skybg on"
