# Performance report: standardize config defaults

Tracking issue: [#26](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/26)

## Decision

- Status: accept in isolation. A third strict-idle repetition and physical-device
  confirmation are optional deferred checks, not release blockers for this
  build-time-only refactor.
- Functional benefit: shipped defaults now come from one neutral,
  machine-independent JSON file. Generated target-local Swift constants keep
  the worker and app consistent without adding runtime parsing or linkage.
- Measured cost: zero release-helper bytes and zero app-executable bytes in
  equal-path clean builds. Five paired startup batches were within launch-time
  noise. Two completed 150-second idle runs had zero wakeup growth and stable
  bounded memory.
- Reason: generation occurs only during development and CI. The installed
  worker still reads config once at startup and performs no additional runtime
  work.

## Revisions

| Role | Branch | Commit | Dirty | Binary SHA-256 |
| --- | --- | --- | --- | --- |
| Baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | no | `8ce79405bf59aa2afd516f1f6e0426887609993cd29d842bcba2fe03abff5a2b` |
| Candidate | `refactor/standardize-config-defaults` | `8ac3154774e0e17a28f9830c6de4336fbc964468` | no | `ae5fc4777c6e99e5c4c4ec2141506f081baaa7d63c5b5a808e0db5ea1791fd97` |

Different checkout paths change Swift build metadata and therefore binary
hashes. Clean baseline and candidate builds from equal-length `/tmp` paths
produced equal `432408`-byte helpers. The normal project-path candidate helper
remained `432552` bytes, exactly matching the frozen baseline size.

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
The user config hash was unchanged before and after every check.

## Implementation shape

- `config/defaults.json` is the editable default-value authority.
- `scripts/generate-config-defaults.swift` creates target-local constants for
  the CLI worker and app support target.
- CI runs the generator in `--check` mode so stale generated files fail fast.
- The app bundles the same neutral defaults file for distribution and settings
  documentation.
- Existing user config is never rewritten merely because defaults changed.
- No JSON parser, shared runtime module, timer, thread, or file watcher was
  added to the running worker.

## Static comparison

| Measurement | Baseline | Candidate | Delta | Delta % |
| --- | ---: | ---: | ---: | ---: |
| Release helper bytes, equal-path clean build | 432408 | 432408 | 0 | 0% |
| App executable bytes, equal-path clean build | 769392 | 769392 | 0 | 0% |
| Signed embedded helper bytes | 448064 | 448064 | 0 | 0% |
| Uncompressed app file bytes | 1390090 | 1391076 | +986 | +0.071% |
| App archive bytes | 438548 | 438924 | +376 | +0.086% |
| Persistent worker threads | 2 | 2 | 0 | 0% |

The archive increase is the checked-in neutral JSON resource and updated
documentation, not executable runtime code. Neither helper links or contains
an `XCTest` or `Testing` marker. Sharing archives contain
`config/defaults.json` and exclude retired machine-specific default names.

## Strict idle

Each completed candidate run used a 10-second warm-up and six 30-second
intervals. The user requested that remaining long measurements be deferred in
favor of implementation completion, so the planned third repetition was
stopped and is not represented as a pass.

| Run | Elapsed s | CPU s | CPU % | Pkg wake | Int wake | Context switches | RSS MiB | Footprint MiB | Threads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 150.076 | 0.000000000 | 0.000000 | 0 | 0 | 0 | 8.312-8.406 | 2.719-2.719 | 2/2 |
| 2 | 150.088 | 0.000826227 | 0.000550 | 0 | 0 | 501 | 8.422-8.875 | 2.750-3.125 | 2/2 |

Both runs had zero package-idle and interrupt-wakeup growth, no socket, no
normal log, no leak, and a completely stopped worker afterward. The second
run's context switches and syscalls occurred without periodic wakeup growth;
the process footprint remained bounded. These results are supporting evidence,
not a claim that an unrun third sample passed.

## Startup workload

Five paired batches launched `--print-config` 200 times per role. The first
cold batch took 1.68 seconds for baseline and 1.57 seconds for candidate.
Four warmed batches measured baseline/candidate at 1.22/1.23, 1.21/1.22,
1.20/1.20, and 1.17/1.23 seconds. The warmed means are approximately 6.00 and
6.10 milliseconds per process, within process-launch and filesystem noise.

Baseline and candidate `--print-config` output hashes matched exactly. This
also verifies that generation did not change effective behavior.

## Safety checks

- [x] No polling loop, periodic timer, watcher, or persistent thread
- [x] No normal logging or network access
- [x] No unbounded state or retained config history
- [x] Config is still loaded once at startup
- [x] Existing user config is byte-for-byte preserved
- [x] Generator drift is checked by CI
- [x] Test/profiling code is absent from release artifacts
- [x] Worker stops completely and stale PID handling still works
- [x] `swift build` and `swift build -c release` pass
- [x] GitHub Actions: 34 tests, 0 failures
- [x] App and lightweight source archives verify
- [ ] Optional third strict-idle repetition run by the maintainer

Local `swift test` remains unavailable because the selected standalone Command
Line Tools installation does not provide XCTest. GitHub Actions supplied the
test, release-linkage, and archive-verification evidence.

## Hardware observations

This refactor does not alter event matching, gesture handling, scroll
transformation, or key posting. No connected MX Master was available during
measurement. A maintainer may still run the existing worker measurement script
and normal hardware smoke test before promotion.

## Interaction result

| Combination | Baseline commit | Combined commit | Result | Report |
| --- | --- | --- | --- | --- |
| Runtime interaction | `32dd841` | not applicable | no runtime change | this report |

The generated constants are target-local and introduce no new runtime
dependency, so this branch does not require a runtime-feature interaction
pair.
