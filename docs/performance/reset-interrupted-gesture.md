# Performance report: event-tap interruption recovery

Tracking issue: [#21](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/21)

## Decision

- Status: accept in isolation; required interaction testing remains pending.
- Functional benefit: an event-tap timeout or user-input disable now cancels an
  active gesture, clears all accumulated state, and disables the movement tap
  without posting an action.
- Measured cost: 160 release-helper bytes. Three paired 150-second idle runs
  showed no periodic wakeups, added thread, leak, socket, log file, or
  systematic CPU/memory regression.
- Reason: recovery executes only for CoreGraphics tap-disabled notifications.
  It adds no work to ordinary mouse, scroll, or idle event paths.

## Revisions

| Role | Branch | Commit | Dirty | Binary SHA-256 |
| --- | --- | --- | --- | --- |
| Baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | no | `8ce79405bf59aa2afd516f1f6e0426887609993cd29d842bcba2fe03abff5a2b` |
| Candidate | `fix/reset-interrupted-gesture` | `a81e8e6df5e9d077b876dfd13622e5364be9c907` | no | `e17767b95a5ca9e19eeb853dca89b178b43688732cc1a09055fb7a28c3b06553` |

The candidate's second commit changes only the test target. The measured
release helper is identical before and after that test-only commit. Clean
baseline and candidate archives were also built from equal-length paths; that
comparison independently produced the same 160-byte delta.

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

Behavior-relevant config: gesture/back/forward buttons `5/3/4`, threshold
`220`, `systemEvents` action backend, inverted desktop direction enabled,
`mxMasterOnly` scroll transform, and EMA smoothing enabled. The config was
read once and was not modified for measurement.

## Implementation shape

- Both mapped event taps already own the same `GestureMapper`; no coordinator
  or additional callback allocation was introduced.
- A tap-disabled notification asks that mapper to end an active gesture before
  deciding whether the affected tap should be re-enabled.
- Ending the gesture uses the existing activity callback to disable the
  movement tap. The primary tap remains intended to run and is re-enabled.
- Cancellation is idempotent. An idle or repeated notification performs no
  state transition and never posts a keyboard action.
- Detailed cancellation output remains behind `DebugLogger`'s autoclosure
  gate. Normal mode emits only the existing one-time concise recovery notice.

## Static comparison

| Measurement | Baseline | Candidate | Delta | Delta % |
| --- | ---: | ---: | ---: | ---: |
| Release helper bytes | 432552 | 432712 | +160 | +0.037% |
| App archive bytes | 438548 | 438982 | +434 | +0.099% |
| Uncompressed app file bytes | 1389978 | 1390138 | +160 | +0.012% |
| Linked runtime frameworks | 15 | 15 | 0 | 0% |
| Persistent worker threads | 2 | 2 | 0 | 0% |

The GUI executable was byte-identical in the app bundles; the complete
uncompressed app delta is exactly the helper's 160-byte increase. The larger
ZIP delta is ad-hoc signature/compression variation. Neither release helper
links or contains an `XCTest` or `Testing` marker.

## Strict idle

Each run used a 10-second warm-up, six 30-second intervals, normal worker
mode, unchanged config, and the same machine state. Raw evidence stayed
outside Git.

| Role | Run | CPU s | CPU % | Pkg wake | Int wake | Ctx | Mach | Unix | RSS MiB | Footprint MiB | Threads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline | 1 | 0.006125570 | 0.004082 | 0 | 0 | 1734 | 16063 | 3210 | 7.594-8.875 | 3.047-3.157 | 2/2 |
| baseline | 2 | 0.001568138 | 0.001045 | 0 | 0 | 496 | 4178 | 834 | 8.453-8.875 | 2.704-3.079 | 2/2 |
| baseline | 3 | 0.000000000 | 0.000000 | 0 | 0 | 0 | 0 | 0 | 8.453-8.453 | 2.704-2.704 | 2/2 |
| candidate | 1 | 0.001128933 | 0.000752 | 0 | 0 | 340 | 3115 | 622 | 8.312-8.719 | 2.704-3.016 | 2/2 |
| candidate | 2 | 0.001164228 | 0.000776 | 0 | 0 | 447 | 3335 | 666 | 8.469-8.781 | 2.766-3.094 | 2/2 |
| candidate | 3 | 0.001993764 | 0.001328 | 0 | 0 | 764 | 5660 | 1130 | 8.438-8.766 | 2.735-3.094 | 2/2 |

| Three-run mean | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| CPU-time seconds | 0.002565 | 0.001429 | -0.001136 |
| Average CPU, one core | 0.001709% | 0.000952% | -0.000757 points |
| Context switches | 743 | 517 | -226 |
| RSS minimum MiB | 8.167 | 8.406 | +0.240 |
| RSS maximum MiB | 8.734 | 8.755 | +0.021 |
| Footprint minimum MiB | 2.818 | 2.735 | -0.083 |
| Footprint maximum MiB | 2.980 | 3.068 | +0.089 |

Both roles crossed the aspirational 8 MiB RSS target, so three pairs were run
as required. Pairwise RSS and footprint differences changed sign; there was
no monotonic growth or candidate-only retention. Every run had zero
package-idle and interrupt-wakeup growth, no leak, no socket, no normal log
file, two threads, and a fully stopped worker afterward.

## Active workloads

An external temporary CoreGraphics poster sent 12,000 same-location pointer
events to the HID tap. It restored normal lifecycle through the public CLI and
was not committed or packaged.

Inactive workload: the movement tap remained disabled. Across three runs,
baseline averaged 0.491 microseconds total worker CPU (0.041 ns per posted
event) and candidate averaged 0.933 microseconds (0.078 ns/event). Those
sub-microsecond counter changes are below useful resolution. Package-idle
wakeup growth was zero for every run.

Active workload: a synthetic gesture-button down enabled the movement tap,
12,000 zero-distance movement events were posted, and button-up ended the
hold. No threshold was crossed and no keyboard action was sent.

| Active metric, four-run mean | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| Worker CPU-time seconds | 0.003352 | 0.003208 | -0.000144 |
| CPU per posted event | 279.3 ns | 267.4 ns | -11.9 ns |
| Context switches | 4105 | 4048 | -57 |
| Maximum RSS observed | 11.016 MiB | 11.031 MiB | +0.016 MiB |
| Maximum footprint observed | 5.235 MiB | 5.313 MiB | +0.078 MiB |
| Package-idle wakeups | 0 | 0 | 0 |
| Thread range | 2-3 | 2-3 | 0 |

Individual active results ranged from 250-322 ns/event for baseline and
252-281 ns/event for candidate. That natural spread is much larger than the
mean delta and the new cancellation method is not called by this workload.

Focused CI also executed 12,000 begin, below-threshold movement, and recovery
cycles directly against `GestureMapper`. It completed in 0.007 seconds in a
debug test process, produced exactly 12,000 activation and cancellation
callbacks, and ended with inactive, unconsumed, zeroed state. This is a
bounded-state correctness workload, not a release-worker CPU claim.

## Safety checks

- [x] No polling loop or periodic timer
- [x] No additional persistent worker thread
- [x] No normal logging or network access
- [x] No unbounded state or retained event history
- [x] Scroll events are not reposted
- [x] Debug formatting remains gated
- [x] Test/profiling code is absent from release artifacts
- [x] Worker stops completely and stale PID handling still works
- [x] `swift build` and `swift build -c release` pass
- [x] GitHub Actions: 37 tests, 0 failures
- [x] App and lightweight source archives verify

Local `swift test` remains unavailable because the selected standalone Command
Line Tools installation does not provide XCTest. GitHub Actions supplied the
test evidence and also passed release linkage and archive checks.

## Hardware observations

Doctor confirmed Accessibility and Input Monitoring permission but did not
detect a connected MX Master during measurement. Pointer workloads therefore
used synthetic HID-posted events. A real tap timeout or sleep/reconnect event
was not forced. Physical recovery and ordinary gestures must be checked with
#23 in the required interaction branch before either change is merged.

## Interaction result

| Combination | Baseline commit | Combined commit | Result | Report |
| --- | --- | --- | --- | --- |
| #21 + #23 gesture recovery | `32dd841` | pending | pending | pending |
| All accepted runtime changes | `32dd841` | pending | pending | pending |

This isolated acceptance does not authorize merging until the required
interaction checks pass.
