#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_BIN="$PROJECT_DIR/.build/release/mx3-lite"
WRAPPER="/usr/local/bin/mxmaster"
WRAPPER_DIR="$(dirname "$WRAPPER")"

cd "$PROJECT_DIR"
swift build -c release

if [[ ! -x "$RELEASE_BIN" ]]; then
  echo "mx3-lite release binary was not created at: $RELEASE_BIN" >&2
  exit 1
fi

TMP_WRAPPER="$(mktemp)"
trap 'rm -f "$TMP_WRAPPER"' EXIT

run_sudo() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [[ -t 0 ]]; then
    sudo "$@"
  else
    echo "Cannot run sudo in this non-interactive shell. Re-run this script from an interactive terminal if installation is needed." >&2
    return 1
  fi
}

cat > "$TMP_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail

MX3_LITE="$RELEASE_BIN"

usage() {
  cat <<'USAGE'
Usage:
  mxmaster on
  mxmaster off
  mxmaster toggle
  mxmaster status
  mxmaster debug
  mxmaster scroll-debug
  mxmaster config
  mxmaster test-left
  mxmaster test-right
  mxmaster test-up
USAGE
}

if [[ ! -x "\$MX3_LITE" ]]; then
  echo "mx3-lite release binary is missing or not executable: \$MX3_LITE" >&2
  echo "Run scripts/install.sh from the mx3-lite project again." >&2
  exit 1
fi

cmd="\${1:-}"
if [[ \$# -gt 0 ]]; then
  shift
fi

case "\$cmd" in
  on)
    exec "\$MX3_LITE" on "\$@"
    ;;
  off)
    exec "\$MX3_LITE" off "\$@"
    ;;
  toggle)
    exec "\$MX3_LITE" toggle "\$@"
    ;;
  status)
    exec "\$MX3_LITE" status "\$@"
    ;;
  debug)
    exec "\$MX3_LITE" --run-foreground --debug "\$@"
    ;;
  scroll-debug)
    exec "\$MX3_LITE" --debug-scroll "\$@"
    ;;
  config)
    exec "\$MX3_LITE" --print-config "\$@"
    ;;
  test-left)
    exec "\$MX3_LITE" --test-left "\$@"
    ;;
  test-right)
    exec "\$MX3_LITE" --test-right "\$@"
    ;;
  test-up)
    exec "\$MX3_LITE" --test-up "\$@"
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown mxmaster command: \$cmd" >&2
    usage >&2
    exit 64
    ;;
esac
EOF

chmod 755 "$TMP_WRAPPER"

if [[ -f "$WRAPPER" ]] && cmp -s "$TMP_WRAPPER" "$WRAPPER"; then
  echo "mxmaster wrapper is already installed at $WRAPPER"
  echo "Wrapper target: $RELEASE_BIN"
  echo "No launch agent was installed. Start and stop manually with mxmaster on/off."
  exit 0
fi

if [[ ! -d "$WRAPPER_DIR" ]]; then
  if [[ -w "$(dirname "$WRAPPER_DIR")" ]]; then
    mkdir -p "$WRAPPER_DIR"
  else
    run_sudo mkdir -p "$WRAPPER_DIR"
  fi
fi

if [[ -w "$WRAPPER_DIR" ]]; then
  install -m 755 "$TMP_WRAPPER" "$WRAPPER"
else
  run_sudo install -m 755 "$TMP_WRAPPER" "$WRAPPER"
fi

echo "Installed mxmaster wrapper at $WRAPPER"
echo "Wrapper target: $RELEASE_BIN"
echo "No launch agent was installed. Start and stop manually with mxmaster on/off."
