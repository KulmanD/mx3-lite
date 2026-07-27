#!/usr/bin/env bash
set -euo pipefail

EXPECTED_ARCH=""
REQUIRE_GATEKEEPER=false
ARCHIVE=""

usage() {
  cat <<'EOF'
Usage: scripts/verify-release.sh --arch arm64|x86_64 [--require-gatekeeper] ARCHIVE.zip

Verifies archive extraction, bundle structure, signatures, architecture,
privacy-sensitive contents, and optional Gatekeeper acceptance.
EOF
}

while (($#)); do
  case "$1" in
    --arch)
      [[ $# -ge 2 ]] || { echo "--arch requires a value" >&2; exit 64; }
      EXPECTED_ARCH="$2"
      shift 2
      ;;
    --require-gatekeeper)
      REQUIRE_GATEKEEPER=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
    *)
      [[ -z "$ARCHIVE" ]] || { echo "Only one archive may be verified" >&2; exit 64; }
      ARCHIVE="$1"
      shift
      ;;
  esac
done

case "$EXPECTED_ARCH" in
  arm64|x86_64) ;;
  *)
    echo "--arch must be arm64 or x86_64" >&2
    exit 64
    ;;
esac

[[ -f "$ARCHIVE" ]] || { echo "Archive not found: $ARCHIVE" >&2; exit 66; }

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mx3-lite-release-verify.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
ditto -x -k "$ARCHIVE" "$TEMP_DIR/extracted"
APP="$TEMP_DIR/extracted/mx3-lite.app"
CONTENTS="$APP/Contents"

test -x "$CONTENTS/MacOS/mx3-lite-app"
test -x "$CONTENTS/Helpers/mx3-lite"
test -f "$CONTENTS/Resources/defaults.json"
plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --verify --strict "$CONTENTS/Helpers/mx3-lite"
codesign --verify --strict "$CONTENTS/MacOS/mx3-lite-app"
codesign --verify --deep --strict "$APP"

for executable in "$CONTENTS/Helpers/mx3-lite" "$CONTENTS/MacOS/mx3-lite-app"; do
  actual_archs="$(lipo -archs "$executable")"
  if [[ "$actual_archs" != "$EXPECTED_ARCH" ]]; then
    echo "Architecture mismatch in $executable: expected $EXPECTED_ARCH, found $actual_archs" >&2
    exit 1
  fi
done

archive_entries="$(unzip -Z1 "$ARCHIVE" | sed 's:/$::')"
if grep -Eq '(^|/)(\.build|\.git|\.github|\.swiftpm|DerivedData|Tests)(/|$)|(^|/)config\.json$|(^|/)scripts/performance(/|$)' <<<"$archive_entries"; then
  echo "Release archive contains development or user-specific files" >&2
  exit 1
fi

embedded_user_path="$(find "$APP" -type f -exec strings {} \; | grep -E '/Users/[^/]+/' | head -n 1 || true)"
if [[ -n "$embedded_user_path" ]]; then
  echo "Release archive contains an embedded user path: $embedded_user_path" >&2
  exit 1
fi

if "$REQUIRE_GATEKEEPER"; then
  spctl --assess --type execute --verbose=4 "$APP"
  xcrun stapler validate "$APP"
fi

if otool -L "$CONTENTS/Helpers/mx3-lite" | grep -Eq 'XCTest|Testing'; then
  echo "Release helper links a test framework" >&2
  exit 1
fi

echo "Verified $ARCHIVE"
echo "Architecture: $EXPECTED_ARCH"
echo "Gatekeeper required: $REQUIRE_GATEKEEPER"
