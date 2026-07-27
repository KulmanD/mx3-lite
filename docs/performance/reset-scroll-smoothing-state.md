# Performance report: reset scroll smoothing state

Tracking issue: #24

## Decision

- Status: accept in isolation; #25 interaction and physical-device testing remain
  pending.
- Functional benefit: EMA and inertia smoothing no longer carry stale momentum
  across a 200 ms idle gap or a direction reversal. Each axis resets
  independently on reversal.
- Measured cost: 480 release-helper bytes, one optional event timestamp, and no
  timer, thread, history buffer, polling, idle wakeup, or retained event.
- Reason: the state reset is event-driven and bounded. Five paired
  10-million-event runs measured a worst mean increase of 2.47 ns per event.
  Three 150-second idle runs found no systematic CPU or memory regression.

## Revisions

| Role | Branch | Commit | Dirty | Binary SHA-256 |
| --- | --- | --- | --- | --- |
| Baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | no | `8ce79405bf59aa2afd516f1f6e0426887609993cd29d842bcba2fe03abff5a2b` |
| Candidate | `perf/reset-scroll-smoothing-state` | `4bad40e876f187079921e95b90c857ff1eaecafa` | no | `828b8bb9d47b2563d48bde167a6b7deb4f40ffc69d0dd390fd84095b819f33b4` |

## Environment

| Item | Value |
| --- | --- |
| Mac | MacBook Pro `Mac16,8` |
| CPU architecture | `arm64` |
| macOS | 26.5.1 (25F80) |
| Swift | Apple Swift 6.3.2, Swift 5.9 package mode |
| Connection | unavailable during measurement |
| Device | doctor reported no matching MX Master |
| Config SHA-256 | `b25df5cf7b6d9baa14a32efb3ddd883eefa0820ba2e9dbd2218e575c32d1f75a` |

Behavior-relevant config remained unchanged: gesture/back/forward buttons
`5/3/4`, threshold `220`, `systemEvents` action backend, inverted desktop
direction enabled, `mxMasterOnly` scroll transform, and EMA smoothing enabled.
The user config was read once and was not modified.

## Implementation shape

- A transformed EMA or inertia event records its CoreGraphics event timestamp.
- A backwards timestamp or a gap of at least 200 ms clears four scalar
  smoothing values before processing the new event.
- A direction reversal clears only that axis's previous output and inertia
  carry, preserving independent horizontal and vertical sequences.
- `dampenSpikes` is stateless across events and skips all sequence bookkeeping.
- Disabled smoothing and non-MX pass-through events retain no sequence
  timestamp.
- No timer releases inertia. It remains optional and advances only when a
  scroll event is already being handled.

## Static comparison

| Measurement | Baseline | Candidate | Delta | Delta % |
| --- | ---: | ---: | ---: | ---: |
| Release helper bytes | 432552 | 433032 | +480 | +0.111% |
| App archive bytes | 438548 | 438912 | +364 | +0.083% |
| Uncompressed app file bytes | 1389978 | 1390762 | +784 | +0.056% |
| Linked runtime frameworks | 15 | 15 | 0 | 0% |
| Persistent worker threads | 2 | 2 | 0 | 0% |

The app-file and ZIP differences include ad-hoc signature/compression
variation; the bare release-helper delta is authoritative. Neither helper
links or contains an `XCTest` or `Testing` marker.

## Strict idle

Each candidate run used a 10-second warm-up and six 30-second intervals. The
three frozen baseline runs from `reset-interrupted-gesture.md` are reused
because machine, config, permissions, and connected-device state were
unchanged.

| Role | Run | CPU s | CPU % | Pkg wake | Int wake | Ctx | Mach | Unix | RSS MiB | Footprint MiB | Threads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| candidate | 1 | 0.004140160 | 0.002759 | 0 | 0 | 2761 | 16229 | 3244 | 8.797-8.875 | 3.079-3.157 | 2/2 |
| candidate | 2 | 0.000000000 | 0.000000 | 0 | 0 | 0 | 0 | 0 | 8.391-8.391 | 2.719-2.719 | 2/2 |
| candidate | 3 | 0.000000000 | 0.000000 | 0 | 0 | 0 | 0 | 0 | 8.344-8.344 | 2.672-2.672 | 2/2 |

| Three-run mean | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| CPU-time seconds | 0.002565 | 0.001380 | -0.001185 |
| Average CPU, one core | 0.001709% | 0.000920% | -0.000789 points |
| Context switches | 743 | 920 | +177 |
| RSS minimum MiB | 8.167 | 8.510 | +0.343 |
| RSS maximum MiB | 8.734 | 8.536 | -0.198 |
| Footprint minimum MiB | 2.818 | 2.823 | +0.005 |
| Footprint maximum MiB | 2.980 | 2.849 | -0.131 |

The context-switch mean is dominated by one externally induced sample; the
next two complete windows recorded zero CPU-time, wakeup, context-switch, and
syscall growth. Both roles cross the aspirational 8 MiB RSS target, while the
candidate's maximum RSS and footprint means were lower than baseline. Every
run had zero package-idle and interrupt-wakeup growth, two threads, no leak,
socket, or normal log, and a completely stopped worker afterward.

## Active workload

A temporary uncommitted release-only command exercised the real
`ScrollTransformer` with one reused CGEvent. Baseline and candidate harness
sources were identical. Each role processed five paired runs of 10 million
events per workload, alternating execution order. The harness is absent from
the branch, release helper, app bundle, and sharing archive.

| Workload | Mode | Baseline ns/event | Candidate ns/event | Delta |
| --- | --- | ---: | ---: | ---: |
| continuous ratchet | EMA | 66.763 | 68.695 | +1.932 |
| direction reversal every event | EMA | 62.322 | 64.790 | +2.468 |
| 300 ms gap every event | EMA | 63.871 | 64.764 | +0.893 |
| free-spin burst | dampenSpikes | 60.258 | 59.309 | -0.949 |
| direction reversal every event | inertia | 62.681 | 64.704 | +2.023 |

Continuous output checksums matched baseline. Reversal checksums changed as
intended because stale opposite-direction state is no longer blended into the
new sequence. Sparse and free-spin output checksums remained unchanged. The
worst mean active delta is about 2.5 ns/event and cannot create idle work.

CI tests cover continuous EMA behavior, independent-axis reversal, exact idle
boundary reset, backwards/disabled timestamps, inertia carry reset, bounded
state, and non-MX pass-through. All 37 tests passed.

## Safety checks

- [x] No polling loop or periodic timer
- [x] No additional persistent worker thread
- [x] No normal logging or network access
- [x] No unbounded state, retained event, or history buffer
- [x] Scroll events are modified in place and are not reposted
- [x] Debug formatting remains gated
- [x] Test/profiling code is absent from release artifacts
- [x] Worker stops completely and stale PID handling still works
- [x] `swift build` and `swift build -c release` pass
- [x] GitHub Actions: 37 tests, 0 failures
- [x] App and lightweight source archives verify

Local `swift test` remains unavailable because the selected standalone Command
Line Tools installation does not provide XCTest. GitHub Actions supplied the
test, release-linkage, and archive-verification evidence.

## Hardware observations

Doctor confirmed the required permissions but did not detect a connected MX
Master during measurement. Deterministic tests and the release benchmark
verify state transitions and cost, but physical ratchet/free-spin feel,
trackpad coexistence, and reconnect behavior remain required on the #24 + #25
interaction branch.

## Interaction result

| Combination | Baseline commit | Combined commit | Result | Report |
| --- | --- | --- | --- | --- |
| #24 + #25 scroll processing | `32dd841` | pending | pending | pending |
| All accepted runtime changes | `32dd841` | pending | pending | pending |

This isolated acceptance does not authorize merging until the required
interaction checks pass.
