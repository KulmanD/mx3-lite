#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DESTINATION="${MX3_LITE_APP_DESTINATION:-$HOME/Applications/mx3-lite.app}"
SKIP_WRAPPER=false

if [[ "$APP_DESTINATION" != /* || "$(basename "$APP_DESTINATION")" != "mx3-lite.app" ]]; then
  echo "MX3_LITE_APP_DESTINATION must be an absolute path ending in mx3-lite.app" >&2
  exit 64
fi

if [[ "${1:-}" == "--skip-wrapper" ]]; then
  SKIP_WRAPPER=true
  shift
fi
if [[ $# -ne 0 ]]; then
  echo "usage: scripts/install-app.sh [--skip-wrapper]" >&2
  exit 64
fi

bash "$SCRIPT_DIR/build-app.sh"
"$PROJECT_DIR/.build/release/mx3-lite" off >/dev/null

mkdir -p "$(dirname "$APP_DESTINATION")"
TEMP_DESTINATION="$(mktemp -d "$(dirname "$APP_DESTINATION")/.mx3-lite-install.XXXXXX")/mx3-lite.app"
trap 'rm -rf "$(dirname "$TEMP_DESTINATION")"' EXIT

ditto "$PROJECT_DIR/dist/mx3-lite.app" "$TEMP_DESTINATION"
codesign --verify --deep --strict "$TEMP_DESTINATION"
rm -rf "$APP_DESTINATION"
mv "$TEMP_DESTINATION" "$APP_DESTINATION"

echo "Installed app at $APP_DESTINATION"
echo "The app and worker do not start automatically."

if [[ "$SKIP_WRAPPER" == true ]]; then
  echo "Skipped /usr/local/bin/mxmaster wrapper installation."
else
  MX3_LITE_BINARY="$APP_DESTINATION/Contents/Helpers/mx3-lite" bash "$SCRIPT_DIR/install.sh"
fi
