#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_VERSION="${APP_VERSION:-0.3.0}"
APP_BUNDLE="$PROJECT_DIR/dist/mx3-lite.app"
CONTENTS="$APP_BUNDLE/Contents"

if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "APP_VERSION must use semantic version form, for example 0.3.0" >&2
  exit 64
fi

cd "$PROJECT_DIR"
swift build -c release --product mx3-lite
swift build -c release --product mx3-lite-app

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$CONTENTS/Resources"

install -m 755 .build/release/mx3-lite-app "$CONTENTS/MacOS/mx3-lite-app"
install -m 755 .build/release/mx3-lite "$CONTENTS/Helpers/mx3-lite"
install -m 644 app/Info.plist "$CONTENTS/Info.plist"
install -m 644 config/README.md "$CONTENTS/Resources/README.md"
install -m 644 config/defaults.json "$CONTENTS/Resources/defaults.json"
install -m 644 docs/PERFORMANCE.md "$CONTENTS/Resources/PERFORMANCE.md"
install -m 644 docs/APP_ARCHITECTURE.md "$CONTENTS/Resources/APP_ARCHITECTURE.md"

plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS/Info.plist"

TEMP_DIR="$(mktemp -d "$PROJECT_DIR/.mx3-lite-app-build.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
swift scripts/generate-app-icon.swift "$TEMP_DIR/AppIcon.iconset"
iconutil -c icns "$TEMP_DIR/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_BUNDLE"
plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
echo "Version: $APP_VERSION"
echo "Signing: ad-hoc (Developer ID signing and notarization are required for public distribution)"
echo "No launch agent or login item was created."
