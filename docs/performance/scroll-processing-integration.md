# Performance report: scroll processing integration

Tracking issues: #24 and #25

## Decision

- Status: implementation complete; formal repeated idle, combined active-event,
  and physical MX Master checks are delegated to the maintainer.
- Functional result: scroll-sequence resets and consistent CoreGraphics delta
  fields coexist in one in-place transformation path.
- Static cost: 1072 helper bytes over the frozen baseline, 48 bytes above the
  sum of the two isolated helper deltas.
- Merge gate: do not promote the runtime pair until the maintainer records the
  deferred measurements below.

## Revisions

| Role | Branch | Commit | Dirty | Helper bytes |
| --- | --- | --- | --- | ---: |
| Baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | no | 432552 |
| Candidate | `perf/scroll-processing-integration` | `03c8bd6` | no | 433624 |

The production integration ends at `068bdb0`; later commits add combined tests
and development-only measurement orchestration. Those files are excluded from
the helper, app bundle, and sharing ZIP.

## Combined behavior

- EMA and optional inertia state reset after a 200 ms event gap, a backwards
  event timestamp, or a direction reversal.
- Vertical and horizontal axes reset independently.
- Smoothing state remains five bounded scalar values; no history is retained.
- `dampenSpikes` remains stateless across events.
- Integer, fixed-point, and point-delta fields are updated together only for
  active axes.
- Scroll phase, momentum phase, and scroll count are preserved.
- Non-MX events in `mxMasterOnly` mode pass through unchanged and do not retain
  smoothing sequence state.
- The same incoming `CGEvent` is modified and returned; no scroll event is
  reposted.

## Deterministic checks

- [x] Both accepted production commit sets applied to the frozen baseline
- [x] Shared production callback merged without conflict
- [x] Test conflict resolved by retaining both isolated suites
- [x] Added vertical idle-reset plus all-representation assertion
- [x] Added horizontal reversal plus all-representation assertion
- [x] `swift build`
- [x] `swift build -c release`
- [x] Release helper contains no test framework linkage
- [x] No timer, dispatch source, delayed task, or scroll repost added
- [x] One 10-second measurement-runner smoke test completed and stopped worker
- [x] User config hash remained unchanged
- [x] GitHub Actions: 43 tests, 0 failures
- [ ] Three strict-idle runs with normal 10-second warm-up
- [ ] Combined fixed-event-count scroll benchmark
- [ ] MX Master ratchet/free-spin and trackpad coexistence checks

The 10-second smoke run validates the measurement script, not performance. It
used no warm-up and therefore observed startup transients, including a
temporary third thread. It must not be cited as normal idle evidence.

## Static comparison

| Measurement | Baseline | #24 isolated | #25 isolated | Combined |
| --- | ---: | ---: | ---: | ---: |
| Helper bytes | 432552 | 433032 | 433096 | 433624 |
| Delta | - | +480 | +544 | +1072 |

The isolated deltas sum to 1024 bytes. The combined image is 48 bytes larger
than that sum, consistent with compiler code layout/alignment but still
reported as interaction cost. The branch adds no persistent thread, timer,
buffer, runtime test support, or new framework.

## Deferred maintainer command

Run the standard repeated idle protocol from this branch:

```bash
bash scripts/performance/measure-candidate.sh \
  --label scroll-processing-integration
```

The command builds once, performs three 150-second runs, keeps each run in a
separate `/tmp` directory, verifies the config hash is unchanged, and confirms
that no worker remains. Add aggregate results to this report before promotion.

For physical behavior, verify ratchet and free-spin wheel modes, vertical and
horizontal scrolling, sequence pauses, rapid reversals, and MacBook trackpad
coexistence with `scrollTransformMode = "mxMasterOnly"`.

## Safety checks

- [x] Event-driven only; no polling or background timer
- [x] No additional persistent worker thread
- [x] Bounded scalar smoothing state
- [x] No retained event or history buffer
- [x] No normal log or network access
- [x] Scroll event modified in place, never reposted
- [x] Debug result construction remains gated by `captureDebug`
- [x] Measurement code excluded from release artifacts
- [x] Worker stops completely after scripted checks

## Interaction result

| Combination | Baseline commit | Combined commit | Result |
| --- | --- | --- | --- |
| #24 + #25 | `32dd841` | `068bdb0` | implementation complete; measurement pending |

This branch is ready for CI and maintainer measurement, but the deferred gates
remain required before merging the runtime pair.
