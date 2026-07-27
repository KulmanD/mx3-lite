# Interaction report: gesture recovery

Candidates: #21 and #23

## Decision

- Status: accept the optimized combination.
- Functional result: tap interruption and stale-hold cancellation share one
  gesture state safely. Both clear timestamps, movement/scroll totals,
  consumption, and active state, disable the movement tap, and post no action.
- Measured cost: 608 release-helper bytes over baseline. Active movement and
  idle behavior remain within or better than measured baseline variation.
- Interaction found: the direct combination initially crossed a 16 KiB Mach-O
  `__TEXT` alignment boundary. Removing redundant/dynamic recovery diagnostics
  avoided that binary-size jump without changing behavior.

## Revisions

| Role | Ref | Commit | Binary bytes | Binary SHA-256 |
| --- | --- | --- | ---: | --- |
| Baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | 432552 | `8ce79405bf59aa2afd516f1f6e0426887609993cd29d842bcba2fe03abff5a2b` |
| Combined runtime | `perf/gesture-recovery-integration` | `271faf6` | 433160 | `ca44742142774799e3c5d8fb807f906ecb92d95e8d81a1891e5fdde2ea35fb19` |

Equal-length clean-path builds measured 432408 and 433016 bytes, confirming
the same 608-byte delta.

## Composition

The branch starts directly from `performance-baseline-v1` and cherry-picks the
runtime/test commits from #21 and #23 without merge commits. Conflict
resolution retained both cancellation entry points and one test-only state
accessor. The shared reset assertions now verify that `startedAt` is also nil
after event-tap interruption.

The optimized interaction changes diagnostics only:

- event-tap recovery keeps one concise normal message and one gated debug
  message, but removes duplicate mapper text;
- stale cancellation keeps a gated static message instead of formatting an
  elapsed `Double` that is not needed for recovery.

## Binary interaction

| Build | `__text` | C strings | `__TEXT` segment | Helper bytes |
| --- | ---: | ---: | ---: | ---: |
| Baseline clean build | 172736 | 8801 | 212992 | 432408 |
| Direct combination | 174312 | 8945 | 229376 | 449720 |
| Optimized combination | 173668 | 8881 | 212992 | 433016 |

The direct combination contained about 1.7 KiB of additional text/string data
but crossed a 16 KiB segment-alignment boundary, producing a 17,312-byte file
increase. The optimized combination stays below that boundary and is only 608
bytes larger than baseline. This validates the requirement to measure feature
interactions rather than add isolated deltas arithmetically.

| Distribution measurement | Baseline | Combined | Delta |
| --- | ---: | ---: | ---: |
| App archive bytes | 438548 | 439146 | +598 |
| Uncompressed app file bytes | 1389978 | 1390698 | +720 |
| Persistent worker threads | 2 | 2 | 0 |

The GUI helper is unchanged; signed-helper and ZIP differences include ad-hoc
signature/compression variation. No test or performance helper is linked or
packaged.

## Strict idle

Three combined runs used a 10-second warm-up and six 30-second intervals.

| Run | CPU s | CPU % | Pkg wake | Int wake | Ctx | RSS MiB | Footprint MiB | Threads |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.004045211 | 0.002695 | 0 | 0 | 1388 | 8.453-8.891 | 2.844-3.204 | 2/2 |
| 2 | 0.003523633 | 0.002348 | 0 | 0 | 1487 | 7.656-8.859 | 2.782-3.157 | 2/2 |
| 3 | 0.010839933 | 0.007223 | 0 | 0 | 6928 | 8.953-9.016 | 3.188-3.251 | 2/2 |

Run 3 was noisier, so a fresh adjacent baseline/candidate pair was added under
the same current system conditions.

| Current-condition pair | Baseline | Combined | Delta |
| --- | ---: | ---: | ---: |
| CPU-time seconds | 0.003349623 | 0.005104394 | +0.001754771 |
| Average CPU, one core | 0.002232% | 0.003401% | +0.001169 points |
| Maximum RSS | 8.953 MiB | 8.953 MiB | 0 |
| Maximum footprint | 3.157 MiB | 3.188 MiB | +0.031 MiB |
| Package/interrupt wakeups | 0/0 | 0/0 | 0/0 |
| Threads | 2/2 | 2/2 | 0 |

All combined runs had zero package-idle and interrupt-wakeup growth, no leak,
socket, or normal log file, two threads, and a fully stopped worker. CPU
variation remained a few milliseconds over 150 seconds and did not correspond
to a timer or memory-growth signature. RSS crossed the existing 8 MiB target
in both roles but showed no combined retention.

## Active workload

Four combined runs held synthetic gesture button 5 and posted 12,000
same-location movement events with alternating deltas, matching the isolated
#23 workload.

| Active metric | Frozen baseline | Combined | Delta |
| --- | ---: | ---: | ---: |
| Worker CPU-time, four-run mean | 0.003301 s | 0.003024 s | -0.000277 s |
| CPU per posted event | 275.1 ns | 252.0 ns | -23.1 ns |
| Context switches | 4229 | 3924 | -305 |
| Maximum RSS observed | 11.234 MiB | 10.906 MiB | -0.328 MiB |
| Maximum footprint observed | 5.469 MiB | 5.141 MiB | -0.328 MiB |
| Package-idle wakeups | 0 | 0 | 0 |
| Thread range | 2-4 | 2-3 | no persistent change |

The combined range was 247-256 ns/event. There is no active CPU interaction
between timeout recovery and stale-hold checking.

## Functional verification

GitHub Actions passed 43 tests, including:

- idle, active, below-threshold, consumed, and repeated tap interruptions;
- stale movement, scroll, gesture-down, gesture-up, and immediate reuse;
- 12,000 interruption cycles and 12,000 stale-cancellation cycles;
- shared reset assertions covering timestamp, location, totals, consumption,
  and activity callback counts;
- release linkage and lightweight archive checks.

Doctor did not detect a connected MX Master during the run. Physical
tap-timeout and missed-release behavior could not be forced, so that limitation
remains explicit; deterministic combined state transitions and performance
gates pass.

## Safety checks

- [x] No timer, polling, sleep, or periodic clock check
- [x] No additional persistent thread
- [x] No normal logging, network access, or event repost loop
- [x] No retained history or unbounded state
- [x] Neither cancellation path posts an action
- [x] Combined binary-size cliff identified and removed
- [x] Worker lifecycle and packaging remain clean
- [x] Combined CI passes

## Integration result

The optimized combined runtime is approved for the later all-accepted-runtime
integration branch. The two feature PRs should receive the diagnostic
optimization before they are considered mergeable; they remain draft until
the final runtime-set gate is complete.
