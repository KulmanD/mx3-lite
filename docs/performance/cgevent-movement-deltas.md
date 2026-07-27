# Performance report: CGEvent movement deltas

Tracking issue: #22

## Decision

- Status: reject.
- Functional result: synthetic tests prove deltas continue accumulating when
  cursor location is unchanged, but prior live MX Master 3S testing found this
  same raw-delta approach unreliable for vertical gestures.
- Measured cost: the helper is 1,072 bytes smaller, but four active runs
  averaged 2.4% more worker CPU and 2.7% more context switches.
- Reason: a smaller binary does not justify restoring a known gesture
  reliability regression. No current physical-device result contradicts the
  prior live evidence, so this branch must not merge.

## Revisions

| Role | Branch | Commit | Dirty | Binary SHA-256 |
| --- | --- | --- | --- | --- |
| Baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | no | `8ce79405bf59aa2afd516f1f6e0426887609993cd29d842bcba2fe03abff5a2b` |
| Candidate | `fix/use-cgevent-movement-deltas` | `93f77fc983d04dd30ae6965ad18c8578464bcdeb` | no | `b3279f153e59936131a4fb4cced45c7b2e1b856f06637b513a90df5d5d6e1b06` |

Clean source archives were also built from equal-length paths. They measured
432472 baseline bytes and 431400 candidate bytes, confirming the same
1,072-byte delta without build-path bias.

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
`5/3/4`, threshold `220`, desktop-direction inversion enabled, and the
`systemEvents` action backend.

## Implementation shape

- `mouseEventDeltaX` and `mouseEventDeltaY` replace location subtraction.
- The stored `CGPoint` and its update arithmetic are removed from
  `GestureState`; there is no fallback or second accumulation path.
- Event masks, threshold order, inversion semantics, one-action consumption,
  side-button suppression, and scroll behavior are unchanged.
- No timer, polling path, history, thread, or persistent allocation is added.

## Static comparison

| Measurement | Baseline | Candidate | Delta | Delta % |
| --- | ---: | ---: | ---: | ---: |
| Release helper bytes | 432552 | 431480 | -1072 | -0.248% |
| App archive bytes | 438548 | 437942 | -606 | -0.138% |
| Uncompressed app file bytes | 1389978 | 1389098 | -880 | -0.063% |
| Linked runtime frameworks | 15 | 15 | 0 | 0% |
| Persistent worker threads | 2 | 2 | 0 | 0% |

The app ZIP and signed-helper differences include ad-hoc signing and
compression variation. The path-controlled bare helper comparison is the
authoritative code-size delta. Neither release helper links or contains an
`XCTest` or `Testing` marker.

## Strict idle

The candidate used a 10-second warm-up and six 30-second intervals. Today's
three baseline runs from the frozen tag are recorded in
`reset-interrupted-gesture.md`; they are reused because machine, config hash,
permissions, and device state were unchanged.

| Measurement | Baseline three-run mean | Candidate exploratory run |
| --- | ---: | ---: |
| Elapsed seconds | 150.074 | 150.079 |
| CPU-time delta seconds | 0.002565 | 0.000760 |
| Average CPU, one core | 0.001709% | 0.000506% |
| Package-idle wakeup delta | 0 | 0 |
| Interrupt-wakeup delta | 0 | 0 |
| Context-switch delta | 743 | 251 |
| RSS range | 7.594-8.875 MiB | 8.516-8.813 MiB |
| Physical-footprint range | 2.704-3.157 MiB | 2.844-3.188 MiB |
| Threads minimum / maximum | 2/2 | 2/2 |

The candidate had zero leak, socket, normal log file, package-idle wakeup, and
interrupt-wakeup growth, and stopped fully afterward. It was not repeated
three times despite crossing the 8 MiB RSS target because the branch had
already failed the functional gate; this result rules out hidden idle
architecture changes but is not an acceptance claim.

## Active workload

An external temporary CoreGraphics poster held synthetic gesture button 5 and
sent 12,000 same-location movement events. Delta X alternated `+1/-1` and
delta Y alternated `-1/+1`, so both fields were read without crossing the
threshold. Each role ran four times in alternating order.

| Active metric, four-run mean | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| Worker CPU-time seconds | 0.003101 | 0.003174 | +0.000073 |
| CPU per posted event | 258.4 ns | 264.5 ns | +6.1 ns (+2.4%) |
| Context switches | 3749 | 3849 | +100 (+2.7%) |
| Maximum RSS observed | 10.953 MiB | 10.906 MiB | -0.047 MiB |
| Maximum footprint observed | 5.219 MiB | 5.204 MiB | -0.015 MiB |
| Package-idle wakeups | 0 | 0 | 0 |
| Thread range | 2-3 | 2-3 | 0 |

Candidate results ranged from 254-281 ns/event; baseline ranged from
250-275 ns/event. The increase is small in absolute terms, but there is no
functional reason to pay it after the live reliability failure.

Focused CI tests covered left/right/up/down accumulation, inversion, a strict
threshold boundary, one action per hold, diagonal precedence, side-button
suppression, and movement with an unchanged cursor location. All 36 repository
tests passed. Threshold crossing was tested without posting a real desktop
shortcut.

## Safety checks

- [x] No polling loop or periodic timer
- [x] No additional persistent worker thread
- [x] No normal logging or network access
- [x] No unbounded state or retained event history
- [x] Event-tap masks are unchanged
- [x] Debug formatting remains gated
- [x] Tests are absent from release artifacts
- [x] `swift build` and `swift build -c release` pass
- [x] GitHub Actions: 36 tests, 0 failures
- [x] Candidate app archive verifies

## Hardware observations

The existing location-based implementation was introduced after raw deltas
failed to detect vertical gestures reliably on the tested MX Master 3S. This
branch intentionally recreates raw-delta-only accumulation and adds no device
handling that could explain a different live result. Doctor did not detect an
MX Master during the current run, so only synthetic behavior was newly tested.

The conservative decision is therefore rejection. A future reconsideration
would require new physical event logs showing why the earlier vertical deltas
were missing and a design that addresses that cause without weakening the
current location path.

## Interaction result

No interaction branch is required for a rejected candidate. Issue #23 remains
independent and should continue from `performance-baseline-v1`.
