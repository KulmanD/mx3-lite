# Performance report: all accepted runtime changes

Accepted candidates: [#21](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/21),
[#23](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/23),
[#24](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/24),
and [#25](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/25).

Issue #22 is intentionally excluded because its isolated experiment was
rejected.

## Decision

- Status: cumulative implementation complete; formal repeated idle, combined
  active-event, and physical-device validation are delegated to the
  maintainer.
- Functional result: gesture interruption recovery, stale-hold cancellation,
  smoothing sequence reset, and scroll delta consistency coexist with direct
  interaction coverage.
- Static cost: 976 helper bytes over the frozen baseline after optimization.
- Merge gate: keep this PR draft until the maintainer records the deferred
  runtime and hardware evidence.

## Revisions

| Role | Branch | Commit | Dirty | Helper bytes | `__TEXT` bytes |
| --- | --- | --- | --- | ---: | ---: |
| Baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | no | 432552 | 212992 |
| Direct cumulative build | local pre-optimization | production composition | no | 450616 | 229376 |
| Optimized candidate | `perf/all-runtime-integration` | `96001c8` | no | 433528 | 212992 |

The production candidate ends at `96001c8`. Tests and measurement scripts are
development-only and excluded from every app and lightweight source archive.

## Nonlinear size interaction

The direct cumulative build ended only 240 bytes beyond the smaller Mach-O
text layout and therefore allocated another 16 KiB page. Its apparent 18064
byte helper increase was predominantly alignment, not executable behavior.

| Build | `__text` | C strings | Total text sections | `__TEXT` segment | Helper bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Direct cumulative | 174288 | 8881 | 208294 | 229376 | 450616 |
| Optimized cumulative | 173524 | 8801 | 207422 | 212992 | 433528 |

The optimization removes a stored `DebugLogger` reference and dynamic event
type formatting from the rare event-tap recovery notice. Recovery still emits
one concise normal stderr message, clears gesture state, disables movement
capture, re-enables only the intended tap, and never posts an action. Detailed
normal event formatting remains absent; existing foreground event debug stays
behind its debug gates.

This saves 17088 bytes from the direct image and makes the final helper only
976 bytes (+0.226%) larger than baseline. For comparison:

- isolated accepted deltas sum to 1808 bytes;
- optimized gesture pair plus scroll pair sum to 1680 bytes;
- final cumulative delta is 976 bytes.

The final result proves that interaction-aware optimization is materially
better than adding isolated size measurements.

## Combined functional checks

- Event-tap interruption clears active gesture state idempotently.
- A stale 30-second hold cancels on the next relevant event using the incoming
  monotonic event timestamp; there is no timer.
- Recovery hands stale or post-interruption scroll events back to inactive
  scrolling without suppressing them.
- Combined tests verify those scroll events receive consistent integer,
  fixed-point, and point-delta fields.
- EMA/inertia state resets after event gaps, backwards timestamps, and
  per-axis direction reversals.
- Smoothing state remains bounded scalar data and `dampenSpikes` remains
  stateless.
- Scroll events are modified in place and never reposted.
- MacBook trackpad events remain pass-through in `mxMasterOnly` mode when not
  classified as MX Master.

## Static and packaging checks

| Measurement | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| Release helper bytes | 432552 | 433528 | +976 |
| App archive bytes | 438548 | 439322 | +774 |
| Uncompressed app file bytes | 1389978 | 1391258 | +1280 |
| Linked test frameworks | 0 | 0 | 0 |

The app ZIP and signed bundle include code-signature/compression variation;
the bare helper is the authoritative runtime comparison. Source and app
packaging completed, and no test or `scripts/performance/` file entered either
end-user artifact.

## Deterministic checks

- [x] Accepted production commits composed directly on the frozen baseline
- [x] Rejected #22 implementation excluded
- [x] Gesture-pair interaction tests retained
- [x] Scroll-pair interaction tests retained
- [x] Added stale-cancel plus transformed-scroll integration test
- [x] Added interruption-recovery plus transformed-scroll integration test
- [x] `swift build`
- [x] `swift build -c release`
- [x] Shell syntax and measurement-runner smoke validation
- [x] App and lightweight source archive verification
- [x] Start, Status, Stop; no process remains after Stop
- [x] User config hash unchanged
- [x] Binary-size cliff reproduced and removed
- [ ] GitHub Actions: expected 56 tests
- [ ] Three strict-idle maintainer runs
- [ ] Combined gesture and scroll fixed-workload measurements
- [ ] Physical MX Master gesture, ratchet, free-spin, and trackpad checks

Local `swift test` remains unavailable because the selected standalone Command
Line Tools installation does not provide XCTest. GitHub Actions supplies the
deterministic test evidence.

## Deferred maintainer command

Run the standard cumulative idle protocol from this branch:

```bash
bash scripts/performance/measure-candidate.sh \
  --label all-runtime-integration
```

The script builds once, writes three independent 150-second runs under `/tmp`,
verifies the user config hash is unchanged, and confirms the worker is fully
stopped. Do not copy raw evidence into Git because it may include local paths;
record reviewed aggregate values here.

Physical validation should cover gesture left/right/up, one action per hold,
side-button suppression during a hold, missed-release recovery, ratchet and
free-spin scrolling, rapid direction reversal, 200 ms scroll pauses, and
MacBook trackpad coexistence.

## Safety checks

- [x] Event-driven only; no polling, periodic timer, or background task
- [x] No additional persistent worker thread
- [x] No network access, updater, telemetry, or normal log
- [x] No unbounded state, history buffer, or retained event
- [x] No synthetic input loop; scroll is modified in place
- [x] Synthetic keys fire only when a gesture action is consumed
- [x] Recovery never posts a key action
- [x] Debug event formatting remains gated
- [x] Test and profiling code absent from release artifacts
- [x] Lifecycle leaves no process after Stop

## Interaction result

| Combination | Baseline | Candidate | Result |
| --- | --- | --- | --- |
| #21 + #23 gesture recovery | `32dd841` | gesture pair `271faf6` | accepted |
| #24 + #25 scroll processing | `32dd841` | scroll pair `068bdb0` | implementation complete; measurement pending |
| All accepted runtime changes | `32dd841` | `96001c8` | implementation complete; measurement pending |

The cumulative branch is ready for CI and the maintainer-run gates, but it is
not represented as performance-approved until those deferred checks are added.
