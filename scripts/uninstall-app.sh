#!/usr/bin/env bash
set -euo pipefail

APP_DESTINATION="${MX3_LITE_APP_DESTINATION:-$HOME/Applications/mx3-lite.app}"
HELPER="$APP_DESTINATION/Contents/Helpers/mx3-lite"
WRAPPER="${MX3_MASTER_WRAPPER:-/usr/local/bin/mxmaster}"

if [[ "$APP_DESTINATION" != /* || "$(basename "$APP_DESTINATION")" != "mx3-lite.app" ]]; then
  echo "MX3_LITE_APP_DESTINATION must be an absolute path ending in mx3-lite.app" >&2
  exit 64
fi

if [[ -x "$HELPER" ]]; then
  "$HELPER" off >/dev/null || true
fi

if [[ -f "$WRAPPER" ]] && grep -Fq "MX3_LITE=\"$HELPER\"" "$WRAPPER"; then
  echo "The mxmaster wrapper points into this app. Remove it first with:"
  echo "  bash scripts/uninstall.sh"
  exit 1
fi

rm -rf "$APP_DESTINATION"
echo "Removed $APP_DESTINATION"
echo "Config was preserved at $HOME/Library/Application Support/mx3-lite/config.json"
