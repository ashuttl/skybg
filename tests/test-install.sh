#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d /tmp/skybg-install-test.XXXXXX)
trap 'rm -rf -- "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/fake-bin" "$TEST_HOME/xdg-config" "$TEST_HOME/xdg-state"
cp /usr/bin/true "$TEST_HOME/fake-bin/systemctl"

run_isolated() {
  HOME="$TEST_HOME" \
    XDG_CONFIG_HOME="$TEST_HOME/xdg-config" \
    XDG_STATE_HOME="$TEST_HOME/xdg-state" \
    PATH="$TEST_HOME/fake-bin:$PATH" \
    "$@"
}

run_isolated "$ROOT/install.sh" >/dev/null
test -x "$TEST_HOME/.local/bin/skybg"
test -f "$TEST_HOME/xdg-config/systemd/user/skybg.service"
test -f "$TEST_HOME/xdg-config/systemd/user/skybg.timer"
test -x "$TEST_HOME/.config/omarchy/hooks/theme-set.d/skybg-retint"

run_isolated "$ROOT/uninstall.sh" --purge >/dev/null
test ! -e "$TEST_HOME/.local/bin/skybg"
test ! -e "$TEST_HOME/xdg-config/systemd/user/skybg.service"
test ! -e "$TEST_HOME/xdg-config/systemd/user/skybg.timer"
test ! -e "$TEST_HOME/.config/omarchy/hooks/theme-set.d/skybg-retint"

echo "install/uninstall isolation: ok"
