#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_VERSION="${APP_VERSION:-0.3.0}"
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"
ARCHES=()

usage() {
  cat <<'EOF'
Usage: scripts/package-release.sh [options]

Options:
  --arch arm64|x86_64      Build one architecture; repeat for both (default: both)
  --sign-identity IDENTITY Developer ID Application identity; default is ad-hoc
  --notary-profile PROFILE notarytool keychain profile; requires Developer ID
  -h, --help               Show this help

Environment equivalents:
  APP_VERSION, DEVELOPER_ID_APPLICATION, NOTARYTOOL_PROFILE
EOF
}

while (($#)); do
  case "$1" in
    --arch)
      [[ $# -ge 2 ]] || { echo "--arch requires a value" >&2; exit 64; }
      ARCHES+=("$2")
      shift 2
      ;;
    --sign-identity)
      [[ $# -ge 2 ]] || { echo "--sign-identity requires a value" >&2; exit 64; }
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --notary-profile)
      [[ $# -ge 2 ]] || { echo "--notary-profile requires a value" >&2; exit 64; }
      NOTARY_PROFILE="$2"
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

if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "APP_VERSION must use semantic version form, for example 0.3.0" >&2
  exit 64
fi

if ((${#ARCHES[@]} == 0)); then
  ARCHES=(arm64 x86_64)
fi

for arch in "${ARCHES[@]}"; do
  case "$arch" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 64 ;;
  esac
done

if [[ -n "$NOTARY_PROFILE" && "$SIGN_IDENTITY" == "-" ]]; then
  echo "Notarization requires a Developer ID Application signing identity" >&2
  exit 64
fi

RELEASE_DIR="$PROJECT_DIR/dist/releases/v$APP_VERSION"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

for arch in "${ARCHES[@]}"; do
  STAGE_DIR="$PROJECT_DIR/dist/release-stage/$arch"
  APP="$STAGE_DIR/mx3-lite.app"
  ARCHIVE_NAME="mx3-lite-app-v$APP_VERSION-macos-$arch.zip"
  ARCHIVE="$RELEASE_DIR/$ARCHIVE_NAME"

  bash "$SCRIPT_DIR/build-release-app.sh" \
    --arch "$arch" \
    --sign-identity "$SIGN_IDENTITY" \
    --output "$APP"

  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ARCHIVE"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
  fi

  verify_args=(--arch "$arch")
  if [[ -n "$NOTARY_PROFILE" ]]; then
    verify_args+=(--require-gatekeeper)
  fi
  bash "$SCRIPT_DIR/verify-release.sh" "${verify_args[@]}" "$ARCHIVE"
done

(
  cd "$RELEASE_DIR"
  shasum -a 256 ./*.zip > CHECKSUMS.txt
  shasum -a 256 -c CHECKSUMS.txt
)

echo "Created release artifacts in $RELEASE_DIR"
cat "$RELEASE_DIR/CHECKSUMS.txt"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "These archives are ad-hoc signed validation artifacts, not public release artifacts."
elif [[ -z "$NOTARY_PROFILE" ]]; then
  echo "These archives are Developer ID signed but not notarized."
else
  echo "These archives are Developer ID signed, notarized, stapled, and Gatekeeper verified."
fi
