#!/usr/bin/env bash
set -euo pipefail

WRAPPER="/usr/local/bin/mxmaster"

if [[ ! -e "$WRAPPER" ]]; then
  echo "mxmaster wrapper is not installed at $WRAPPER"
  exit 0
fi

if [[ -w "$(dirname "$WRAPPER")" ]]; then
  rm -f "$WRAPPER"
else
  sudo rm -f "$WRAPPER"
fi

echo "Removed $WRAPPER"
