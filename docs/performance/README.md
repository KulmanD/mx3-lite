# Performance experiment protocol

This directory contains development evidence used to decide whether a proposed
mx3-lite change is worth merging. It does not contain runtime functionality.

The primary constraint is architectural: the normal worker must remain
event-driven. A change must not add polling, periodic timers, background health
checks, normal logging, network access, or an additional persistent thread.

## Fixed baseline

Before implementing an experiment:

1. Record the exact clean `main` commit.
2. Build the release helper with `swift build -c release --product mx3-lite`.
3. Record its SHA-256, size, architecture, linked libraries, macOS version,
   hardware model, Swift version, and parsed config.
4. Run the strict-idle measurement for at least 150 seconds.
5. Use the same machine, config, permissions, connected devices, test duration,
   and workload for the candidate branch.

All independent feature branches in one experiment series should start from
the same recorded baseline commit. Do not merge one candidate into `main`
before the other isolated measurements are complete.

## Measurement helper

Build the release helper, stop any existing worker, and run:

```bash
bash scripts/performance/measure-worker.sh \
  --label main-baseline \
  --duration 150 \
  --interval 30 \
  --warmup 10
```

The script refuses to disturb an existing worker. It starts the selected
binary in normal mode, samples it with public macOS `libproc` interfaces, runs
`lsof`, `vmmap`, and `leaks` after the timed window, and stops the worker on
exit. It does not synthesize mouse, scroll, or keyboard input.

Results are written under `/tmp` unless `--output` is supplied. Raw output is
kept outside Git. Copy only reviewed aggregate values into the branch report;
raw output may contain local paths or configuration details.

The sampling process creates a small amount of external measurement activity.
Use the same interval for baseline and candidate, and repeat a noisy result at
least three times.

## Required measurements

- strict idle CPU-time delta over at least 150 seconds
- package-idle and interrupt-wakeup deltas
- context-switch and Mach/Unix syscall deltas
- worker thread count
- RSS and physical-footprint minimum and maximum
- bounded memory during the feature-specific active workload
- active CPU time for a fixed event count or fixed-duration workload
- release helper and app archive sizes
- open network sockets and normal-mode log files
- leak result where available
- 25 start, duplicate-start, status, and stop cycles for lifecycle changes
- confirmation that release binaries do not link XCTest or Testing

## Acceptance rules

- Idle CPU and periodic wakeups must show no systematic regression.
- Worker RSS should target 8 MiB or less, with no sustained growth.
- A candidate must not show a systematic RSS or physical-footprint increase
  over the fixed baseline. If either result is noisy or crosses the target,
  repeat both baseline and candidate at least three times before deciding.
- The normal worker should remain at two threads.
- Constant-size state is acceptable; unbounded histories are not.
- Every binary-size increase must be reported.
- Functional value and active-event cost must both be considered.
- A branch that fails its budget is rejected or redesigned, not merged first
  and justified afterward.

Approximately zero idle CPU means no measurable CPU-time growth during the
test window. It does not mean that a process consumes mathematically zero
resources.

## Interaction testing

Individually acceptable branches are tested again on temporary
`perf/candidate-integration`:

1. Start from the fixed baseline commit.
2. Apply one accepted candidate at a time.
3. Run the complete baseline after each addition.
4. Test related pairs, then all accepted runtime changes together.
5. Compare the combined delta with `main` and with the sum of individual
   deltas.
6. Treat an unexplained combined regression as an interaction defect.
7. Delete the temporary branch after the final combination is accepted or
   rejected.

The minimum related groups are gesture recovery plus stale-hold handling,
movement-delta plus stale-hold handling, smoothing reset plus scroll-field
preservation, and the complete accepted runtime set.

## Distribution boundary

The `scripts/performance/` directory is excluded from app and lightweight
source archives. Tests and measurement helpers may exist in the repository,
but they must not be linked into the helper, copied into the app bundle, or
included in end-user sharing packages.
