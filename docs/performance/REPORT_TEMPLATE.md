# Performance report: FEATURE

## Decision

- Status: pending | accept | redesign | reject
- Functional benefit:
- Measured cost:
- Reason:

## Revisions

| Role | Branch | Commit | Dirty | Binary SHA-256 |
| --- | --- | --- | --- | --- |
| Baseline | `main` |  | no |  |
| Candidate |  |  | no |  |

## Environment

| Item | Value |
| --- | --- |
| Mac |  |
| CPU architecture |  |
| macOS |  |
| Swift |  |
| Connection | Bluetooth / receiver / unavailable |
| Device |  |
| Config SHA-256 |  |

List behavior-relevant config values without publishing personal paths or
unrelated user data.

## Static comparison

| Measurement | Baseline | Candidate | Delta | Delta % |
| --- | ---: | ---: | ---: | ---: |
| Release helper bytes |  |  |  |  |
| App archive bytes |  |  |  |  |
| Linked runtime frameworks |  |  |  |  |
| Persistent worker threads |  |  |  |  |

Confirm that neither release helper links XCTest or Testing.

## Strict idle

Use at least 150 seconds and the same sampling interval.

| Measurement | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| Elapsed seconds |  |  |  |
| CPU-time delta seconds |  |  |  |
| Average CPU, one core |  |  |  |
| Package-idle wakeup delta |  |  |  |
| Interrupt-wakeup delta |  |  |  |
| Context-switch delta |  |  |  |
| RSS minimum MiB |  |  |  |
| RSS maximum MiB |  |  |  |
| Physical-footprint minimum MiB |  |  |  |
| Physical-footprint maximum MiB |  |  |  |
| Threads minimum / maximum |  |  |  |

Describe whether the result was repeated and whether variation exceeded the
measurement noise. If RSS exceeds the 8 MiB target, compare repeated baseline
and candidate runs and do not report a pass based on a single lower sample.

## Active workload

Define an exact repeatable workload relevant to the feature. Record event
count or duration, input source, CPU-time delta, wakeups, context switches,
RSS/footprint, and functional outcome.

| Measurement | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| Workload |  |  |  |
| CPU-time delta seconds |  |  |  |
| CPU per event |  |  |  |
| Context-switch delta |  |  |  |
| RSS maximum MiB |  |  |  |
| Physical-footprint maximum MiB |  |  |  |

## Safety checks

- [ ] No polling loop or periodic timer
- [ ] No additional persistent worker thread
- [ ] No normal logging or network access
- [ ] No unbounded state or retained event history
- [ ] Scroll events are not reposted
- [ ] Debug formatting remains gated
- [ ] Test/profiling code is absent from release artifacts
- [ ] Worker stops completely and stale PID handling still works
- [ ] `swift build` and `swift build -c release` pass
- [ ] CI tests pass
- [ ] Lightweight archive verification passes

## Hardware observations

Record device, transport, gesture directions, ratchet/free-spin behavior,
trackpad coexistence, sleep/wake, reconnect behavior, and anything that could
not be tested.

## Interaction result

| Combination | Baseline commit | Combined commit | Result | Report |
| --- | --- | --- | --- | --- |
| Related pair |  |  | pending |  |
| All accepted runtime changes |  |  | pending |  |

An individual pass does not authorize merging until required interaction tests
also pass.
