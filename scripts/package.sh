#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
PARENT_DIR="$(dirname "$PROJECT_DIR")"
OUTPUT_ZIP="$PARENT_DIR/$PROJECT_NAME.zip"

required_paths=(
  ".gitignore"
  "README.md"
  "Package.swift"
  "Sources"
  "Sources/MX3AppSupport"
  "Sources/MX3LiteApp"
  "app/Info.plist"
  "scripts/build-app.sh"
  "scripts/generate-config-defaults.swift"
  "scripts/install.sh"
  "scripts/install-app.sh"
  "scripts/package-app.sh"
  "scripts/uninstall.sh"
  "scripts/uninstall-app.sh"
  "config/README.md"
  "config/defaults.json"
  "docs/PERFORMANCE.md"
  "docs/APP_ARCHITECTURE.md"
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$PROJECT_DIR/$required_path" ]]; then
    echo "Required package path is missing: $PROJECT_DIR/$required_path" >&2
    exit 1
  fi
done

TEMP_DIR="$(mktemp -d "$PARENT_DIR/.mx3-lite-package.XXXXXX")"
TEMP_ZIP="$TEMP_DIR/$PROJECT_NAME.zip"
trap 'rm -rf "$TEMP_DIR"' EXIT

(
  cd "$PARENT_DIR"
  /usr/bin/zip -qry "$TEMP_ZIP" "$PROJECT_NAME" \
    -x "$PROJECT_NAME/.build/*" \
    -x "$PROJECT_NAME/.git/*" \
    -x "$PROJECT_NAME/.swiftpm/*" \
    -x "$PROJECT_NAME/.github/*" \
    -x "$PROJECT_NAME/DerivedData/*" \
    -x "$PROJECT_NAME/dist/*" \
    -x "$PROJECT_NAME/Tests/*" \
    -x "$PROJECT_NAME/scripts/performance/*" \
    -x "$PROJECT_NAME/.mx3-lite-app-build.*/*" \
    -x "$PROJECT_NAME/*.xcodeproj/*" \
    -x "$PROJECT_NAME/*.xcworkspace/*" \
    -x "*/.DS_Store"
)

/usr/bin/unzip -tq "$TEMP_ZIP" >/dev/null

archive_entries="$(/usr/bin/unzip -Z1 "$TEMP_ZIP" | sed 's:/$::')"
for required_path in "${required_paths[@]}"; do
  if ! grep -Fqx "$PROJECT_NAME/$required_path" <<<"$archive_entries"; then
    echo "Package verification failed; archive is missing: $PROJECT_NAME/$required_path" >&2
    exit 1
  fi
done

if grep -Eq "^$PROJECT_NAME/(\.build|\.git|\.github|\.swiftpm|DerivedData|dist|Tests)/|^$PROJECT_NAME/scripts/performance/|^$PROJECT_NAME/\.mx3-lite-app-build\.|/\.DS_Store$" <<<"$archive_entries"; then
  echo "Package verification failed; an excluded path is present." >&2
  exit 1
fi

mv -f "$TEMP_ZIP" "$OUTPUT_ZIP"

echo "Created $OUTPUT_ZIP"
echo "Included: README.md, Package.swift, Sources/, scripts/, config/, docs/, and .gitignore"
echo "Excluded: .build/, .git/, .github/, .swiftpm/, DerivedData/, dist/, Tests/, performance probes, Xcode artifacts, and .DS_Store"
