#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$PROJECT_DIR/.build/release/mx3-lite"
DURATION=150
INTERVAL=30
WARMUP=10
LABEL="worker"
OUTPUT_DIR=""
RUN_LEAKS=true
SOURCE_COMMIT=""

usage() {
  cat <<'USAGE'
Usage: scripts/performance/measure-worker.sh [options]

Options:
  --binary PATH         Release mx3-lite binary to measure
  --duration SECONDS    Measurement duration (default: 150)
  --interval SECONDS    Sample interval (default: 30)
  --warmup SECONDS      Untimed startup warm-up (default: 10)
  --label NAME          Filesystem-safe report label (default: worker)
  --output DIR          Output directory (default: /tmp/mx3-lite-performance-...)
  --source-commit SHA   Commit represented by the measured binary
  --skip-leaks          Skip the post-measurement leaks scan
  -h, --help            Show this help

The script refuses to run while an mx3-lite worker is already active. It starts
the selected release binary in normal mode, samples it externally, and stops it
on exit. It does not post mouse, scroll, or keyboard events.
USAGE
}

require_value() {
  if [[ $# -lt 2 || -z "$2" ]]; then
    echo "Missing value for $1" >&2
    exit 64
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binary)
      require_value "$@"
      BINARY="$2"
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
    --output)
      require_value "$@"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --source-commit)
      require_value "$@"
      SOURCE_COMMIT="$2"
      shift 2
      ;;
    --skip-leaks)
      RUN_LEAKS=false
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

if [[ ! "$DURATION" =~ ^[0-9]+$ || "$DURATION" -lt 10 ]]; then
  echo "--duration must be an integer of at least 10 seconds" >&2
  exit 64
fi
if [[ ! "$INTERVAL" =~ ^[0-9]+$ || "$INTERVAL" -lt 1 || "$INTERVAL" -gt "$DURATION" ]]; then
  echo "--interval must be an integer between 1 and the duration" >&2
  exit 64
fi
if [[ ! "$WARMUP" =~ ^[0-9]+$ || "$WARMUP" -gt 300 ]]; then
  echo "--warmup must be an integer between 0 and 300 seconds" >&2
  exit 64
fi
if [[ ! "$LABEL" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "--label may contain only letters, numbers, dot, underscore, and hyphen" >&2
  exit 64
fi
if [[ ! -x "$BINARY" ]]; then
  echo "Release binary is missing or not executable: $BINARY" >&2
  exit 1
fi

BINARY="$(cd "$(dirname "$BINARY")" && pwd)/$(basename "$BINARY")"
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="/tmp/mx3-lite-performance-$LABEL-$(date -u +%Y%m%dT%H%M%SZ)"
fi
if [[ -d "$OUTPUT_DIR" ]] && [[ -n "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit)" ]]; then
  echo "Refusing to mix evidence in a non-empty output directory: $OUTPUT_DIR" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

status_output="$("$BINARY" status)"
if [[ "$status_output" != *"is stopped"* ]]; then
  echo "Refusing to disturb an existing worker: $status_output" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d /tmp/mx3-lite-performance-tools.XXXXXX)"
WORKER_STARTED=false
cleanup() {
  if [[ "$WORKER_STARTED" == true ]]; then
    "$BINARY" off >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

xcrun clang -O2 -Wall -Wextra -Werror "$SCRIPT_DIR/process_metrics.c" -o "$TEMP_DIR/process_metrics"

if [[ -z "$SOURCE_COMMIT" ]]; then
  SOURCE_COMMIT="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
fi
if [[ -n "$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null || true)" ]]; then
  SOURCE_DIRTY=true
else
  SOURCE_DIRTY=false
fi

"$BINARY" --print-config > "$OUTPUT_DIR/parsed-config.txt"
"$BINARY" doctor --verbose > "$OUTPUT_DIR/doctor.txt" 2>&1 || true

{
  echo "label=$LABEL"
  echo "source_commit=$SOURCE_COMMIT"
  echo "source_dirty=$SOURCE_DIRTY"
  echo "measurement_started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "duration_seconds=$DURATION"
  echo "interval_seconds=$INTERVAL"
  echo "warmup_seconds=$WARMUP"
  echo "binary=$BINARY"
  echo "binary_bytes=$(stat -f %z "$BINARY")"
  echo "binary_sha256=$(shasum -a 256 "$BINARY" | awk '{print $1}')"
  echo "binary_type=$(file -b "$BINARY")"
  echo "hardware=$(sysctl -n hw.model)"
  echo "macos=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "architecture=$(uname -m)"
  echo "swift=$(swift --version 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  echo "config_sha256=$(shasum -a 256 "$HOME/Library/Application Support/mx3-lite/config.json" 2>/dev/null | awk '{print $1}' || printf 'missing')"
} > "$OUTPUT_DIR/metadata.txt"

otool -L "$BINARY" > "$OUTPUT_DIR/linked-libraries.txt"

start_output="$("$BINARY" on)"
WORKER_STARTED=true
pid="$(printf '%s\n' "$start_output" | sed -n 's/.*pid \([0-9][0-9]*\).*/\1/p')"
if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
  echo "Could not identify the worker process: $start_output" >&2
  exit 1
fi
echo "pid=$pid" >> "$OUTPUT_DIR/metadata.txt"

if (( WARMUP > 0 )); then
  sleep "$WARMUP"
fi

echo "timestamp_ns,user_time_ns,system_time_ns,package_idle_wakeups,interrupt_wakeups,resident_bytes,physical_footprint_bytes,lifetime_max_physical_footprint_bytes,context_switches,threads,mach_syscalls,unix_syscalls,instructions,cycles" > "$OUTPUT_DIR/metrics.csv"

elapsed=0
while true; do
  "$TEMP_DIR/process_metrics" "$pid" >> "$OUTPUT_DIR/metrics.csv"
  if (( elapsed >= DURATION )); then
    break
  fi
  remaining=$((DURATION - elapsed))
  sleep_for="$INTERVAL"
  if (( remaining < sleep_for )); then
    sleep_for="$remaining"
  fi
  sleep "$sleep_for"
  elapsed=$((elapsed + sleep_for))
done

if /usr/sbin/lsof -nP -a -p "$pid" -i > "$OUTPUT_DIR/network-sockets.txt"; then
  :
else
  echo "none" > "$OUTPUT_DIR/network-sockets.txt"
fi
/usr/sbin/lsof -nP -p "$pid" > "$OUTPUT_DIR/open-files.txt"
/usr/bin/vmmap -summary "$pid" > "$OUTPUT_DIR/vmmap-summary.txt" 2>&1 || true
if [[ "$RUN_LEAKS" == true ]]; then
  /usr/bin/leaks "$pid" > "$OUTPUT_DIR/leaks.txt" 2>&1 || true
else
  echo "skipped" > "$OUTPUT_DIR/leaks.txt"
fi

awk -F, '
  NR == 2 {
    first_ts=$1; first_user=$2; first_system=$3; first_pkg=$4; first_interrupt=$5;
    first_csw=$9; first_mach=$11; first_unix=$12; min_rss=max_rss=$6;
    min_foot=max_foot=$7; min_threads=max_threads=$10
  }
  NR > 1 {
    last_ts=$1; last_user=$2; last_system=$3; last_pkg=$4; last_interrupt=$5;
    last_csw=$9; last_mach=$11; last_unix=$12;
    if ($6 < min_rss) min_rss=$6; if ($6 > max_rss) max_rss=$6;
    if ($7 < min_foot) min_foot=$7; if ($7 > max_foot) max_foot=$7;
    if ($10 < min_threads) min_threads=$10; if ($10 > max_threads) max_threads=$10
  }
  END {
    elapsed_ns=last_ts-first_ts;
    cpu_ns=(last_user-first_user)+(last_system-first_system);
    cpu_pct=elapsed_ns > 0 ? cpu_ns/elapsed_ns*100 : 0;
    printf "elapsed_seconds=%.3f\n", elapsed_ns/1000000000;
    printf "cpu_time_delta_seconds=%.9f\n", cpu_ns/1000000000;
    printf "average_cpu_percent_one_core=%.6f\n", cpu_pct;
    printf "package_idle_wakeup_delta=%.0f\n", last_pkg-first_pkg;
    printf "interrupt_wakeup_delta=%.0f\n", last_interrupt-first_interrupt;
    printf "context_switch_delta=%.0f\n", last_csw-first_csw;
    printf "mach_syscall_delta=%.0f\n", last_mach-first_mach;
    printf "unix_syscall_delta=%.0f\n", last_unix-first_unix;
    printf "rss_min_bytes=%.0f\n", min_rss;
    printf "rss_max_bytes=%.0f\n", max_rss;
    printf "physical_footprint_min_bytes=%.0f\n", min_foot;
    printf "physical_footprint_max_bytes=%.0f\n", max_foot;
    printf "threads_min=%.0f\n", min_threads;
    printf "threads_max=%.0f\n", max_threads
  }
' "$OUTPUT_DIR/metrics.csv" > "$OUTPUT_DIR/summary.txt"

if [[ "$(cat "$OUTPUT_DIR/network-sockets.txt")" == "none" ]]; then
  echo "network_socket_count=0" >> "$OUTPUT_DIR/summary.txt"
else
  network_socket_count="$(awk 'NR > 1 { count++ } END { print count + 0 }' "$OUTPUT_DIR/network-sockets.txt")"
  echo "network_socket_count=$network_socket_count" >> "$OUTPUT_DIR/summary.txt"
fi
normal_log_count="$(grep -c 'mx3-lite\.log' "$OUTPUT_DIR/open-files.txt" || true)"
echo "open_normal_log_count=$normal_log_count" >> "$OUTPUT_DIR/summary.txt"
leak_count="$(awk '/Process .*: [0-9]+ leaks for/ { print $3; exit }' "$OUTPUT_DIR/leaks.txt")"
echo "leak_count=${leak_count:-unknown}" >> "$OUTPUT_DIR/summary.txt"

"$BINARY" off >/dev/null
WORKER_STARTED=false
if [[ "$("$BINARY" status)" == *"is stopped"* ]]; then
  echo "worker_stopped_after_measurement=true" >> "$OUTPUT_DIR/summary.txt"
else
  echo "worker_stopped_after_measurement=false" >> "$OUTPUT_DIR/summary.txt"
fi
echo "measurement_finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUTPUT_DIR/metadata.txt"

cat "$OUTPUT_DIR/summary.txt"
echo "results=$OUTPUT_DIR"
