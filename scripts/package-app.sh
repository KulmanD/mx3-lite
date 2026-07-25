#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_DIR="$(dirname "$PROJECT_DIR")"
APP_VERSION="${APP_VERSION:-0.3.0}"
ARCHIVE_NAME="mx3-lite-app-v$APP_VERSION.zip"
OUTPUT_ZIP="$PARENT_DIR/$ARCHIVE_NAME"
OUTPUT_SHA="$OUTPUT_ZIP.sha256"

if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "APP_VERSION must use semantic version form, for example 0.3.0" >&2
  exit 64
fi

APP_VERSION="$APP_VERSION" bash "$SCRIPT_DIR/build-app.sh"

TEMP_DIR="$(mktemp -d "$PARENT_DIR/.mx3-lite-app-package.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
TEMP_ZIP="$TEMP_DIR/$ARCHIVE_NAME"
EXTRACT_DIR="$TEMP_DIR/extracted"

ditto -c -k --sequesterRsrc --keepParent "$PROJECT_DIR/dist/mx3-lite.app" "$TEMP_ZIP"
ditto -x -k "$TEMP_ZIP" "$EXTRACT_DIR"

test -x "$EXTRACT_DIR/mx3-lite.app/Contents/MacOS/mx3-lite-app"
test -x "$EXTRACT_DIR/mx3-lite.app/Contents/Helpers/mx3-lite"
plutil -lint "$EXTRACT_DIR/mx3-lite.app/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$EXTRACT_DIR/mx3-lite.app"

mv -f "$TEMP_ZIP" "$OUTPUT_ZIP"
(
  cd "$PARENT_DIR"
  shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)

echo "Created $OUTPUT_ZIP"
cat "$OUTPUT_SHA"
echo "No launch agent, login item, tests, or build directory is included."
