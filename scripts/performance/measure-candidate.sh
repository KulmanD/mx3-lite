#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS=3
DURATION=150
INTERVAL=30
WARMUP=10
LABEL="candidate"
OUTPUT_ROOT=""
SKIP_BUILD=false
SKIP_LEAKS=false

usage() {
  cat <<'EOF'
Usage: scripts/performance/measure-candidate.sh [options]

Options:
  --runs COUNT         Repetitions (default: 3)
  --duration SECONDS   Measured seconds per run (default: 150)
  --interval SECONDS   Sampling interval (default: 30)
  --warmup SECONDS     Warm-up before each run (default: 10)
  --label NAME         Evidence label (default: candidate)
  --output-root DIR    Root evidence directory
  --skip-build         Measure the existing release binary
  --skip-leaks         Skip the leaks scan in each run
  -h, --help           Show this help

This is a development-only wrapper around measure-worker.sh. It never posts
input events and is excluded from sharing and app archives.
EOF
}

require_value() {
  if [[ $# -lt 2 || -z "$2" ]]; then
    echo "Missing value for $1" >&2
    exit 64
  fi
}

while (($#)); do
  case "$1" in
    --runs)
      require_value "$@"
      RUNS="$2"
      shift 2
      ;;
    --duration)
      require_value "$@"
      DURATION="$2"
      shift 2
      ;;
    --interval)
      require_value "$@"
      INTERVAL="$2"
      shift 2
      ;;
    --warmup)
      require_value "$@"
      WARMUP="$2"
      shift 2
      ;;
    --label)
      require_value "$@"
      LABEL="$2"
      shift 2
      ;;
    --output-root)
      require_value "$@"
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --skip-leaks)
      SKIP_LEAKS=true
      shift
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

if [[ ! "$RUNS" =~ ^[0-9]+$ || "$RUNS" -lt 1 || "$RUNS" -gt 20 ]]; then
  echo "--runs must be an integer between 1 and 20" >&2
  exit 64
fi
if [[ ! "$LABEL" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "--label may contain only letters, numbers, dot, underscore, and hyphen" >&2
  exit 64
fi

cd "$PROJECT_DIR"
if [[ "$SKIP_BUILD" == false ]]; then
  swift build -c release --product mx3-lite
fi

BINARY="$PROJECT_DIR/.build/release/mx3-lite"
[[ -x "$BINARY" ]] || { echo "Release binary is missing: $BINARY" >&2; exit 1; }

if [[ -z "$OUTPUT_ROOT" ]]; then
  OUTPUT_ROOT="/tmp/mx3-lite-$LABEL-$(date -u +%Y%m%dT%H%M%SZ)"
fi
if [[ -d "$OUTPUT_ROOT" && -n "$(find "$OUTPUT_ROOT" -mindepth 1 -print -quit)" ]]; then
  echo "Refusing non-empty output root: $OUTPUT_ROOT" >&2
  exit 1
fi
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"

CONFIG="$HOME/Library/Application Support/mx3-lite/config.json"
config_hash() {
  if [[ -f "$CONFIG" ]]; then
    shasum -a 256 "$CONFIG" | awk '{print $1}'
  else
    printf 'missing\n'
  fi
}

before_config_hash="$(config_hash)"
source_commit="$(git rev-parse HEAD)"
{
  echo "label=$LABEL"
  echo "source_commit=$source_commit"
  echo "binary_sha256=$(shasum -a 256 "$BINARY" | awk '{print $1}')"
  echo "binary_bytes=$(stat -f %z "$BINARY")"
  echo "config_sha256_before=$before_config_hash"
} > "$OUTPUT_ROOT/INDEX.txt"

for ((run = 1; run <= RUNS; run++)); do
  args=(
    --binary "$BINARY"
    --duration "$DURATION"
    --interval "$INTERVAL"
    --warmup "$WARMUP"
    --label "$LABEL-run$run"
    --output "$OUTPUT_ROOT/run$run"
    --source-commit "$source_commit"
  )
  if [[ "$SKIP_LEAKS" == true ]]; then
    args+=(--skip-leaks)
  fi

  echo "Running measurement $run of $RUNS"
  bash "$SCRIPT_DIR/measure-worker.sh" "${args[@]}"
  {
    echo
    echo "[run$run]"
    cat "$OUTPUT_ROOT/run$run/summary.txt"
  } >> "$OUTPUT_ROOT/INDEX.txt"
done

after_config_hash="$(config_hash)"
echo "config_sha256_after=$after_config_hash" >> "$OUTPUT_ROOT/INDEX.txt"
if [[ "$before_config_hash" != "$after_config_hash" ]]; then
  echo "User config changed during measurement" >&2
  exit 1
fi

if [[ "$($BINARY status)" != *"is stopped"* ]] || pgrep -x mx3-lite >/dev/null; then
  "$BINARY" off >/dev/null 2>&1 || true
  echo "Worker remained active after measurement" >&2
  exit 1
fi

echo "All $RUNS measurements completed"
echo "results=$OUTPUT_ROOT"
