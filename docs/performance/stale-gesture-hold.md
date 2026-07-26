# Performance report: stale gesture holds

Tracking issue: [#23](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/23)

## Decision

- Status: accept in isolation; #21 interaction testing remains pending.
- Functional benefit: a missed gesture-button release can no longer suppress
  pointer movement indefinitely. The next relevant event after a conservative
  30-second hold cancels the gesture without posting an action.
- Measured cost: 624 release-helper bytes and one optional timestamp in active
  gesture state. No idle wakeup, thread, leak, socket, or log regression was
  found.
- Reason: CGEvent timestamps provide monotonic time on events already being
  processed, avoiding timers, polling, sleeps, and system clock calls.

## Revisions

| Role | Branch | Commit | Dirty | Binary SHA-256 |
| --- | --- | --- | --- | --- |
| Baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | no | `8ce79405bf59aa2afd516f1f6e0426887609993cd29d842bcba2fe03abff5a2b` |
| Candidate | `fix/abort-stale-gesture-holds` | `7aa6ce0a1d2ed99add182695a602f0daebe8c5bd` | no | `3732add5ce51a8ba22f038e6166ecc1ed2769b60756f369ebf229dc09c7884cc` |

The candidate's second commit changes only the test target. Equal-length clean
build paths measured 432472 baseline bytes and 433096 candidate bytes,
confirming the same 624-byte delta.

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
`5/3/4`, threshold `220`, `systemEvents` action backend, and MX-Master-only
scroll transformation.

## Implementation shape

- Gesture begin stores the incoming CGEvent timestamp.
- The timestamp is checked only while an active button, movement, or scroll
  event is already being handled.
- Normal idle scroll stays on its existing inactive branch and performs no
  timestamp access.
- Cancellation clears location, timestamp, movement/scroll totals, consumed
  state, and active state, then disables the movement tap through the existing
  activity callback.
- A stale movement event passes through. A stale scroll event returns to normal
  scroll handling. A new gesture-button down starts a fresh hold immediately.
- Cancellation is idempotent and never calls `KeySender`.

## Static comparison

| Measurement | Baseline | Candidate | Delta | Delta % |
| --- | ---: | ---: | ---: | ---: |
| Release helper bytes | 432552 | 433176 | +624 | +0.144% |
| App archive bytes | 438548 | 439144 | +596 | +0.136% |
| Uncompressed app file bytes | 1389978 | 1390794 | +816 | +0.059% |
| Linked runtime frameworks | 15 | 15 | 0 | 0% |
| Persistent worker threads | 2 | 2 | 0 | 0% |

Signed-helper and ZIP deltas include ad-hoc signature/compression variation;
the path-controlled bare-helper delta is authoritative. The release helper
does not link or contain `XCTest` or `Testing`.

## Strict idle

Each candidate run used a 10-second warm-up and six 30-second intervals. The
three frozen baseline runs in `reset-interrupted-gesture.md` are reused because
the machine, config hash, permission state, and device state were unchanged.

| Role | Run | CPU s | CPU % | Pkg wake | Int wake | Ctx | Mach | Unix | RSS MiB | Footprint MiB | Threads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| candidate | 1 | 0.008933520 | 0.005952 | 0 | 0 | 2986 | 25177 | 5032 | 8.734-8.766 | 3.032-3.063 | 2/2 |
| candidate | 2 | 0.000000000 | 0.000000 | 0 | 0 | 0 | 0 | 0 | 8.438-8.438 | 2.735-2.735 | 2/2 |
| candidate | 3 | 0.000472911 | 0.000315 | 0 | 0 | 165 | 1417 | 282 | 7.469-8.641 | 2.719-3.032 | 2/2 |

| Three-run mean | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| CPU-time seconds | 0.002565 | 0.003135 | +0.000571 |
| Average CPU, one core | 0.001709% | 0.002089% | +0.000380 points |
| Context switches | 743 | 1050 | +307 |
| RSS minimum MiB | 8.167 | 8.214 | +0.047 |
| RSS maximum MiB | 8.734 | 8.615 | -0.120 |
| Footprint minimum MiB | 2.818 | 2.829 | +0.011 |
| Footprint maximum MiB | 2.980 | 2.943 | -0.037 |

The mean CPU difference comes from one non-repeating 8.9 ms sample. The next
run had exactly zero CPU, wakeup, context-switch, and syscall growth; the third
used 0.47 ms. Every candidate run had zero package-idle and interrupt-wakeup
growth, no leak, socket, or normal log file, two threads, and a fully stopped
worker. RSS crossed the 8 MiB target in both roles but showed no candidate
retention or upward trend.

## Active workloads

An external temporary CoreGraphics poster held synthetic gesture button 5 and
sent 12,000 same-location movement events with alternating delta fields. The
events stayed below threshold. Each role ran four times in alternating order.

| Active metric, four-run mean | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| Worker CPU-time seconds | 0.003301 | 0.003002 | -0.000299 |
| CPU per posted event | 275.1 ns | 250.1 ns | -25.0 ns |
| Context switches | 4229 | 3789 | -440 |
| Maximum RSS observed | 11.234 MiB | 10.859 MiB | -0.375 MiB |
| Maximum footprint observed | 5.469 MiB | 5.125 MiB | -0.344 MiB |
| Package-idle wakeups | 0 | 0 | 0 |
| Persistent thread baseline | 2 | 2 | 0 |

The candidate range was 247-253 ns/event; baseline was 265-288 ns/event. The
timestamp comparison therefore caused no measurable active-path regression.
Transient event-poster activity briefly raised sampled threads in both roles;
strict-idle workers remained at two.

Focused CI performed 12,000 begin-plus-stale-movement cancellation cycles in
0.006 seconds in a debug test process. It produced exactly 12,000 activation
and cancellation callbacks and ended with all state cleared. Additional tests
cover normal short holds, stale movement, stale scroll, gesture-button down and
up, idempotence, no action on cancellation, and immediate reuse.

## Safety checks

- [x] No polling loop, timer, sleep, or periodic clock check
- [x] No additional persistent worker thread
- [x] No normal logging or network access
- [x] No history or unbounded state
- [x] Cancellation never posts an action
- [x] Debug formatting remains gated
- [x] Tests are absent from release artifacts
- [x] Worker stops completely after measurement
- [x] `swift build` and `swift build -c release` pass
- [x] GitHub Actions: 38 tests, 0 failures
- [x] Candidate app archive verifies

## Hardware observations

Doctor did not detect an MX Master during measurement, so a real missed
button-up was not induced. Synthetic timestamps and direct mapper tests cover
the deterministic state transitions. Physical long-hold and ordinary gesture
behavior remain required on the #21 + #23 interaction branch.

## Interaction result

| Combination | Baseline commit | Combined commit | Result | Report |
| --- | --- | --- | --- | --- |
| #21 + #23 gesture recovery | `32dd841` | pending | pending | pending |
| All accepted runtime changes | `32dd841` | pending | pending | pending |

This isolated acceptance does not authorize merging until the required
interaction check passes.
