# Performance report: preserve scroll delta fields

Tracking issue: [#25](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/25)

## Decision

- Status: accept in isolation; #24 interaction and physical application
  compatibility testing remain pending.
- Functional benefit: transformed events now carry consistent integer,
  fixed-point, and point deltas on both axes, including fractional continuous
  scrolling. Applications no longer see stale values when they read a
  representation other than the integer fields.
- Measured cost: 544 release-helper bytes and 22-30 ns/event for normal
  one-axis streams. A mixed two-axis EMA workload added 39 ns/event.
- Reason: the additional work occurs only on classified transformed scroll
  events. Three 150-second runs measured exactly zero idle CPU, wakeups,
  context switches, and syscalls, while a 50-million-event run remained
  bounded.

## Revisions

| Role | Branch | Commit | Dirty | Binary SHA-256 |
| --- | --- | --- | --- | --- |
| Baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | no | `8ce79405bf59aa2afd516f1f6e0426887609993cd29d842bcba2fe03abff5a2b` |
| Candidate | `fix/preserve-scroll-delta-fields` | `e34923b7628cd1517fce0a52cec51befc7caa356` | no | `a9417e2ce65bb0a8696d5ec6cfee18977bc823d14caca65810db8f46f2a08db3` |

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

Behavior-relevant config remained unchanged: buttons `5/3/4`, threshold `220`,
`systemEvents` action backend, inverted desktop direction, `mxMasterOnly`
scroll transform, and EMA smoothing. The user config was not modified.

## Representation rules

- The 16.16 fixed-point field, read through CoreGraphics as a scaled `Double`,
  is the precision-preserving transform input when nonzero.
- The integer field remains the fallback for events without a fixed-point
  value.
- Discrete line deltas retain the worker's existing nearest-integer rounding.
- Continuous pixel deltas truncate toward zero as CoreGraphics does, with a
  minimum magnitude of one for a nonzero value.
- Point deltas use the CoreGraphics-generated 10:1 point-to-fixed relationship
  and nearest-integer rounding.
- Both axes are handled independently. An axis with zero precise input and
  zero smoothed output is left untouched.
- Integer, fixed-point, and point fields are written on the original CGEvent.
  The event is returned, never reposted.
- Scroll phase, momentum phase, count, source metadata, and device
  classification fields are never written.

## Static comparison

| Measurement | Baseline | Candidate | Delta | Delta % |
| --- | ---: | ---: | ---: | ---: |
| Release helper bytes | 432552 | 433096 | +544 | +0.126% |
| App archive bytes | 438548 | 439093 | +545 | +0.124% |
| Uncompressed app file bytes | 1389978 | 1390826 | +848 | +0.061% |
| Linked runtime entries | 16 | 16 | 0 | 0% |
| Persistent worker threads | 2 | 2 | 0 | 0% |

The app-file and ZIP differences include ad-hoc signature/compression
variation; the bare helper delta is authoritative. Neither release helper
links or contains an `XCTest` or `Testing` marker.

## Strict idle

Each candidate run used a 10-second warm-up and six 30-second intervals. The
three frozen baseline runs from `reset-interrupted-gesture.md` are reused
because machine, config, permissions, and device state were unchanged.

| Role | Run | CPU s | CPU % | Pkg wake | Int wake | Ctx | Mach | Unix | RSS MiB | Footprint MiB | Threads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| candidate | 1 | 0.000000000 | 0.000000 | 0 | 0 | 0 | 0 | 0 | 8.453-8.453 | 2.782-2.782 | 2/2 |
| candidate | 2 | 0.000000000 | 0.000000 | 0 | 0 | 0 | 0 | 0 | 8.438-8.438 | 2.750-2.750 | 2/2 |
| candidate | 3 | 0.000000000 | 0.000000 | 0 | 0 | 0 | 0 | 0 | 8.453-8.453 | 2.751-2.782 | 2/2 |

| Three-run mean | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| CPU-time seconds | 0.002565 | 0.000000 | -0.002565 |
| Average CPU, one core | 0.001709% | 0.000000% | -0.001709 points |
| Context switches | 743 | 0 | -743 |
| RSS minimum MiB | 8.167 | 8.448 | +0.281 |
| RSS maximum MiB | 8.734 | 8.448 | -0.286 |
| Footprint minimum MiB | 2.818 | 2.761 | -0.057 |
| Footprint maximum MiB | 2.980 | 2.771 | -0.209 |

Both roles cross the aspirational 8 MiB RSS target, while candidate RSS and
footprint were flat in every run. All candidate windows recorded exactly zero
CPU-time, package-idle/interrupt wakeup, context-switch, Mach-syscall, and
Unix-syscall growth. Every run had two threads, no leak, socket, or normal log,
and a fully stopped worker afterward.

## Active workload

Identical temporary release-only commands populated all six delta fields on
one reused CGEvent and invoked the real `ScrollTransformer`. Each role ran five
paired 5-million-event samples per workload in alternating order. The harness
was not committed, linked into production artifacts, or included in archives.

| Workload | Mode | Baseline ns/event | Candidate ns/event | Delta |
| --- | --- | ---: | ---: | ---: |
| mixed ratchet | EMA | 110.582 | 150.027 | +39.445 |
| one-axis free-spin | dampenSpikes | 104.953 | 127.958 | +23.005 |
| fractional horizontal | EMA | 108.811 | 138.682 | +29.871 |
| one-axis reversal | inertia | 105.761 | 127.571 | +21.810 |

At an intentionally high 1,000 transformed events per second, the measured
delta corresponds to roughly 0.002-0.004% of one core. Checksums confirm that
candidate fixed-point and point fields changed with the transformed integer
output; baseline checksums retained stale secondary representations.

A separate 50-million-event fractional workload produced these process peaks:

| Measurement | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| CPU-time seconds | 5.404 | 6.879 | +1.475 |
| Maximum RSS MiB | 7.156 | 7.234 | +0.078 |
| Peak footprint MiB | 2.126 | 2.188 | +0.062 |

The callback retains no event, array, or history and allocates no per-event
state. The small peak difference is consistent with the larger executable
code footprint and remained bounded across all 50 million events.

CI tests cover both-axis inversion, multiplier, acceleration, smoothing,
clamp, fractional horizontal deltas, continuous/discrete rounding, phase and
momentum preservation, and disabled/non-MX pass-through. All 36 tests passed.

## Safety checks

- [x] No polling loop or periodic timer
- [x] No additional persistent worker thread
- [x] No normal logging or network access
- [x] No allocation, retained event, history, or unbounded state
- [x] Scroll events are modified in place and are not reposted
- [x] Trackpad/non-MX pass-through returns before added field work
- [x] Debug formatting remains gated
- [x] Test/profiling code is absent from release artifacts
- [x] Worker stops completely and stale PID handling still works
- [x] `swift build` and `swift build -c release` pass
- [x] GitHub Actions: 36 tests, 0 failures
- [x] App and lightweight source archives verify

Local `swift test` remains unavailable because the selected standalone Command
Line Tools installation does not provide XCTest. GitHub Actions supplied the
test, release-linkage, and archive-verification evidence.

## Hardware observations

No MX Master was detected during measurement. CoreGraphics-generated line and
pixel events supplied deterministic field data, but physical ratchet/free-spin
feel, target-application compatibility, trackpad coexistence, and reconnect
behavior remain required on the #24 + #25 interaction branch.

## Interaction result

| Combination | Baseline commit | Combined commit | Result | Report |
| --- | --- | --- | --- | --- |
| #24 + #25 scroll processing | `32dd841` | pending | pending | pending |
| All accepted runtime changes | `32dd841` | pending | pending | pending |

This isolated acceptance does not authorize merging until the required
interaction check passes.
