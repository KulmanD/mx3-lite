# Performance and interaction release matrix

Tracking issue: [#20](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/20)

## Runtime baseline and branch base

| Item | Value |
| --- | --- |
| Runtime baseline commit | `be09b042d8386083cc49ecba88828a658e6d4257` |
| Experiment branch base | `performance-baseline-v1` |
| Release helper SHA-256 | `8ce79405bf59aa2afd516f1f6e0426887609993cd29d842bcba2fe03abff5a2b` |
| Release helper bytes | `432552` |
| Architecture | `arm64` |
| Swift | Apple Swift 6.3.2, Swift 5.9 package mode |

All isolated feature branches in this series start from the
`performance-baseline-v1` tag, which includes the measurement infrastructure.
Worker comparisons use the runtime baseline values above because issue #20 did
not change the release helper. Runtime candidates are not merged to `main`
until their isolated reports are complete.

## Candidate register

| Issue | Branch | Performance report | Isolated status | Interaction status |
| --- | --- | --- | --- | --- |
| [#21](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/21) | `fix/reset-interrupted-gesture` | `reset-interrupted-gesture.md` | pending | pending |
| [#22](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/22) | `fix/use-cgevent-movement-deltas` | `cgevent-movement-deltas.md` | pending | pending |
| [#23](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/23) | `fix/abort-stale-gesture-holds` | `stale-gesture-hold.md` | pending | pending |
| [#24](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/24) | `perf/reset-scroll-smoothing-state` | `reset-scroll-smoothing-state.md` | pending | pending |
| [#25](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/25) | `fix/preserve-scroll-delta-fields` | `preserve-scroll-delta-fields.md` | accept | pending |
| [#26](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/26) | `refactor/standardize-config-defaults` | `standardize-config-defaults.md` | pending | pending |
| [#27](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/27) | `release/public-distribution-readiness` | `public-distribution-readiness.md` | pending | pending |

Valid isolated states are `pending`, `accept`, `redesign`, and `reject`.

## Required combinations

| Group | Candidates | Reason | Status |
| --- | --- | --- | --- |
| Gesture recovery | #21 + #23 | Both cancel or reset held-gesture state | pending |
| Gesture movement | #22 + #23 | Both execute on active movement paths | pending |
| Scroll processing | #24 + #25 | Both change the transformed scroll callback | pending |
| Runtime set | All isolated runtime candidates marked `accept` | Detect cumulative or nonlinear cost | pending |

## Integration procedure

1. Create temporary `perf/candidate-integration` from
   `performance-baseline-v1`.
2. Apply accepted candidates one at a time without merge commits.
3. Rebuild and rerun strict idle after every addition.
4. Run each feature-specific active workload.
5. Compare the cumulative result with the baseline and individual deltas.
6. Investigate any combined cost that exceeds expected measurement noise.
7. Record the final accept, redesign, or reject decision here.
8. Delete the temporary branch when the decision is complete.

## Issue #20 infrastructure result

This branch changes documentation, source-archive exclusions, CI packaging
checks, and development-only measurement tools. It does not change Swift
worker or app sources.

| Check | Result |
| --- | --- |
| Release helper byte-identical to baseline | pass: `432552` bytes, identical SHA-256 |
| Strict idle measurement | 150.085 s; 0.001569152 s CPU; 0.001046% of one core |
| Idle wakeups | pass: 0 package-idle and 0 interrupt wakeup growth |
| Worker threads | pass: 2 minimum and maximum after 10 s warm-up |
| RSS | 7.547-8.812 MiB; exceeds the 8 MiB target transiently |
| Physical footprint | 3.141-3.157 MiB with no sustained growth |
| Leak result | pass: 0 leaks, 0 leaked bytes |
| No network socket | pass |
| No normal log file | pass |
| Lifecycle | pass: 25 start/duplicate-start/status/stop cycles |
| Development probes absent from sharing ZIP | pass |
| Tests absent from release helper and sharing ZIP | pass |
| App archive size | 438594-byte fresh baseline; 438631-byte candidate (+37 bytes, +0.0084%) |
| Local tests | blocked: selected Command Line Tools do not provide XCTest |
| GitHub Actions tests | pass: unit tests, release build, linkage check, and archive verification |
| Decision | accept |

### Measurement context

- MacBook Pro `Mac16,8`, Apple Silicon
- macOS 26.5.1 (25F80)
- Apple Swift 6.3.2
- 10-second untimed warm-up, then six samples at 30-second intervals
- normal worker mode with debug disabled
- no matching MX Master was detected during this run
- raw evidence remained under `/tmp` and was not committed

No app-bundle input changed on this branch. A fresh baseline build was 504
bytes larger when uncompressed despite producing a 37-byte smaller ZIP, so
the archive difference is build/signing/compression variation rather than an
added runtime artifact.

The current unchanged baseline does not satisfy a literal RSS ceiling of 8
MiB on every sample. Future candidate decisions therefore retain 8 MiB as the
optimization target while requiring repeated, baseline-relative RSS and
physical-footprint comparisons. No branch may claim zero impact by selecting
only a favorable sample.
