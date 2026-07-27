#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_VERSION="${APP_VERSION:-0.3.0}"
TARGET_ARCH=""
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
OUTPUT_APP=""

usage() {
  cat <<'EOF'
Usage: scripts/build-release-app.sh --arch arm64|x86_64 [options]

Options:
  --sign-identity IDENTITY  Developer ID Application identity; default is ad-hoc
  --output PATH             App bundle output path
  -h, --help                Show this help
EOF
}

while (($#)); do
  case "$1" in
    --arch)
      [[ $# -ge 2 ]] || { echo "--arch requires a value" >&2; exit 64; }
      TARGET_ARCH="$2"
      shift 2
      ;;
    --sign-identity)
      [[ $# -ge 2 ]] || { echo "--sign-identity requires a value" >&2; exit 64; }
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a value" >&2; exit 64; }
      OUTPUT_APP="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

case "$TARGET_ARCH" in
  arm64|x86_64) ;;
  *)
    echo "--arch must be arm64 or x86_64" >&2
    exit 64
    ;;
esac

if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "APP_VERSION must use semantic version form, for example 0.3.0" >&2
  exit 64
fi

if [[ -z "$OUTPUT_APP" ]]; then
  OUTPUT_APP="$PROJECT_DIR/dist/release-build/$TARGET_ARCH/mx3-lite.app"
fi

BUILD_DIR="$PROJECT_DIR/.build/public-release/$TARGET_ARCH"
CONTENTS="$OUTPUT_APP/Contents"

cd "$PROJECT_DIR"
swift build -c release --arch "$TARGET_ARCH" --scratch-path "$BUILD_DIR" --product mx3-lite
swift build -c release --arch "$TARGET_ARCH" --scratch-path "$BUILD_DIR" --product mx3-lite-app
BIN_DIR="$(swift build -c release --arch "$TARGET_ARCH" --scratch-path "$BUILD_DIR" --show-bin-path)"

rm -rf "$OUTPUT_APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$CONTENTS/Resources"

install -m 755 "$BIN_DIR/mx3-lite-app" "$CONTENTS/MacOS/mx3-lite-app"
install -m 755 "$BIN_DIR/mx3-lite" "$CONTENTS/Helpers/mx3-lite"
install -m 644 app/Info.plist "$CONTENTS/Info.plist"
install -m 644 config/README.md "$CONTENTS/Resources/README.md"
install -m 644 config/defaults.json "$CONTENTS/Resources/defaults.json"
install -m 644 docs/PERFORMANCE.md "$CONTENTS/Resources/PERFORMANCE.md"
install -m 644 docs/APP_ARCHITECTURE.md "$CONTENTS/Resources/APP_ARCHITECTURE.md"

plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS/Info.plist"

TEMP_DIR="$(mktemp -d "$PROJECT_DIR/.mx3-lite-release-build.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
swift scripts/generate-app-icon.swift "$TEMP_DIR/AppIcon.iconset"
iconutil -c icns "$TEMP_DIR/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"

sign_item() {
  local item="$1"
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$item"
  else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item"
  fi
}

sign_item "$CONTENTS/Helpers/mx3-lite"
sign_item "$CONTENTS/MacOS/mx3-lite-app"
sign_item "$OUTPUT_APP"

plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --verify --strict "$CONTENTS/Helpers/mx3-lite"
codesign --verify --strict "$CONTENTS/MacOS/mx3-lite-app"
codesign --verify --deep --strict "$OUTPUT_APP"

for executable in "$CONTENTS/Helpers/mx3-lite" "$CONTENTS/MacOS/mx3-lite-app"; do
  actual_archs="$(lipo -archs "$executable")"
  if [[ "$actual_archs" != "$TARGET_ARCH" ]]; then
    echo "Unexpected architectures in $executable: $actual_archs" >&2
    exit 1
  fi
done

echo "Built $OUTPUT_APP"
echo "Architecture: $TARGET_ARCH"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Signing: ad-hoc; suitable for validation only"
else
  echo "Signing: $SIGN_IDENTITY"
fi
echo "No launch agent, login item, updater, or network component was added."
