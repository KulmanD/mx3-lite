# Performance report: complete feature candidate

This branch composes the accepted config-defaults work, public-distribution
tooling, and all accepted runtime changes. Rejected Issue #22 remains excluded.

## Decision

- Status: implementation, static validation, packaging, one controlled
  clean-idle measurement, and the maintainer-run physical validation matrix are
  complete; owner publication gates remain.
- Functional result: all accepted issue branches coexist in one buildable,
  packageable source tree.
- Runtime result: exactly the same 433528-byte helper and 212992-byte `__TEXT`
  segment as the optimized runtime-only branch.
- Merge gate: physical validation no longer blocks the candidate. Keep the PR
  draft until the owner makes the separate review and publication decision.

## Revisions

| Role | Branch | Commit | Helper bytes | `__TEXT` bytes |
| --- | --- | --- | ---: | ---: |
| Frozen baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | 432552 | 212992 |
| Runtime-only candidate | `perf/all-runtime-integration` | `96001c8` | 433528 | 212992 |
| Measured complete candidate | `release/final-feature-candidate` | `727060fb03ad76d752d413db41bfa5d5132e3dc8` | 433528 | 212992 |

The complete helper SHA-256 is
`d7b5a19b7530ac5207e7c781c64d6b7d7dd8980f7badfbb568e03553d134916b`.
The hash differs from the runtime-only checkout because build paths and source
tree metadata can affect output, while executable size and every Mach-O text
section measurement are identical.

## Composition

- #21: cancel gestures after event-tap interruption
- #22: rejected and excluded
- #23: cancel stale held gestures on the next relevant event
- #24: reset bounded smoothing state between independent sequences
- #25: preserve integer, fixed-point, and point scroll deltas
- #26: generated target-local constants from neutral `config/defaults.json`
- #27: separate architecture release packaging, verification, signing, and
  optional notarization workflow

The final merge had one documentation conflict in the release matrix. Runtime,
tests, generated defaults, app resources, workflows, and release scripts
merged without conflict.

## Static comparison

| Measurement | Baseline | Complete candidate | Delta |
| --- | ---: | ---: | ---: |
| Release helper bytes | 432552 | 433528 | +976 |
| Helper `__TEXT` bytes | 212992 | 212992 | 0 |
| Standard app archive bytes | 438548 | 439685 | +1137 |
| Standard uncompressed app file bytes | 1389978 | 1392244 | +2266 |
| Apple Silicon validation ZIP | not applicable | 439759 | - |
| Intel validation ZIP | not applicable | 451821 | - |
| Persistent worker threads | 2 baseline | 2 in the controlled idle run | 0 |

The standard app and architecture validation archives use the final complete
tree. App-size deltas include the 976-byte helper change, neutral defaults
resource/documentation updates, and code-signature/compression variation.

## Controlled clean-idle measurement

### Environment

| Item | Value |
| --- | --- |
| Measured commit | `727060fb03ad76d752d413db41bfa5d5132e3dc8` |
| Branch | `release/final-feature-candidate` |
| macOS | 26.5.1 (25F80) |
| Architecture | Apple Silicon / arm64 |
| Mouse | Logitech MX Master 3S |
| Vendor / product ID | `0x046D` / `0xB034` |
| Accessibility / Input Monitoring | granted / granted |
| Worker before measurement | stopped |
| Config | parsed successfully |
| Action backend | `systemEvents` |
| Scroll transform | `mxMasterOnly` |
| Smoothing | `ema`, enabled |
| Gesture threshold | `220` |

The release helper was already built and the worker was stopped before the
measurement. The exact command was:

```bash
bash scripts/performance/measure-candidate.sh \
  --label final-feature-candidate-clean \
  --runs 1 \
  --duration 150 \
  --interval 30 \
  --warmup 10 \
  --skip-build
```

### Raw result

| Metric | Result |
| --- | ---: |
| Measured duration | `150.086 seconds` |
| Worker CPU-time delta | `0.000000000 seconds` |
| Average CPU usage | `0.000000% of one core` |
| Package-idle wakeup delta | `0` |
| Interrupt-wakeup delta | `0` |
| Context-switch delta | `0` |
| Mach syscall delta | `0` |
| Unix syscall delta | `0` |
| Threads | `2`, stable |
| RSS minimum / maximum | `10,600,448 / 10,600,448 bytes` |
| Physical footprint minimum / maximum | `3,375,584 / 3,375,584 bytes` |
| Network sockets | `0` |
| Normal log files open | `0` |
| Worker stopped afterward | yes |

RSS was approximately 10.1 MiB, while physical footprint was approximately
3.22 MiB. The two measurements describe different memory concepts and must not
be treated as interchangeable. Both remained flat during this run.

The original machine-local evidence directory was
`/tmp/mx3-lite-final-feature-candidate-clean-20260727T094422Z`. That path records
where this run was captured and is not accessible on another Mac.

### Framework allocation report

Apple's `leaks` utility reported seven allocations totaling 496 bytes. The root
object was `GPProcessMonitor`, with child allocations inside Apple `IOHIDLib`.
No project-owned or `mx3-lite` symbol appeared in the allocation chain, and RSS
and physical footprint did not grow during the measurement. This is recorded as
a stable framework-rooted process-lifetime allocation for this run, not as
proof that the application is universally leak-free.

### Interpretation and limitations

This controlled run passed the integrated idle CPU, wakeup, thread, memory
stability, socket, logging, and stop-lifecycle gates. It demonstrates no
measured background activity during this specific 150-second window; it does
not establish that every machine, input workload, reconnect, or sleep cycle
will produce identical counters.

An earlier run that included active gesture use is intentionally excluded from
idle evidence. Physical behavior and combined active input remain separate
manual gates.

## Validation performed

- [x] Generated defaults check
- [x] `swift build`
- [x] `swift build -c release`
- [x] All shell syntax checks
- [x] Neutral config resource ownership
- [x] Existing user config SHA-256 unchanged
- [x] Parsed config output unchanged
- [x] Standard app archive fresh extraction and signature verification
- [x] Lightweight source archive verification
- [x] `arm64` archive fresh extraction, architecture, signature, privacy, and checksum checks
- [x] `x86_64` archive fresh extraction, architecture, signature, privacy, and checksum checks
- [x] Release helper does not link XCTest or Testing
- [x] Start, Status, Stop; no worker remains
- [x] No launch agent, login item, updater, telemetry, or normal log added
- [x] GitHub Actions: 56 tests plus arm64 and x86_64 archive jobs
- [x] One controlled 150-second integrated clean-idle measurement
- [x] Maintainer-run MX Master and MacBook trackpad physical validation
- [ ] Controlled combined active-input performance measurement

## Physical validation

On 2026-07-27, the maintainer reported that the complete manual checklist passed
on one Logitech MX Master 3S. These are user-observed functional results, not
automated measurements or a claim of universal compatibility.

### Environment

| Item | Value |
| --- | --- |
| Documentation commit before testing | `ed65a24e2517d552423c1a3938ccbea2e8953910` |
| Runtime candidate commit | `727060fb03ad76d752d413db41bfa5d5132e3dc8` |
| Mac | MacBook Pro `Mac16,8`, Apple Silicon / arm64 |
| macOS | 26.5.1 (25F80) |
| Mouse | Logitech MX Master 3S |
| Vendor / product ID | `0x046D` / `0xB034` |
| Connection transport | not separately recorded |
| Permissions | Accessibility and Input Monitoring granted |
| Config | `systemEvents`, `mxMasterOnly`, EMA smoothing, threshold `220` |
| Button IDs | gesture `5`, back `3`, forward `4` |

The direct `doctor --verbose` check reported `ready`, detected one MX Master 3S,
parsed the config, confirmed both permissions, and found the worker initially
stopped with no PID metadata. The installed wrapper did not expose `doctor`, so
that check was run through the release helper directly. During physical testing,
status checks reported one worker at PID `69105`. Final shutdown reported
stopped, no matching worker, and no stale PID metadata.

### Results

| Area | Result | Coverage |
| --- | --- | --- |
| Gestures | pass | left, right, up, one action per hold, repeated gestures, below-threshold movement, partial release, stale hold cancellation, and immediate reuse |
| Synthetic-key safety | pass | no stuck modifier and no key characters or escape text in Terminal/text input |
| Side buttons | pass | back and forward in Safari and Finder; gesture button did not leak as normal input; other buttons remained unaffected |
| MX Master scrolling | pass | slow/fast ratchet, free-spin, reversal, horizontal input, pause/resume, no post-pause jump, and no incorrect residual inertia |
| Application coverage | pass | scrolling in Safari, Finder, and Terminal or another native application |
| MacBook trackpad | pass | vertical/horizontal scrolling and gestures remained normal; mouse-only smoothing did not alter trackpad behavior |
| Mouse power cycle | pass | gestures, scrolling, and side buttons worked after turning the mouse off and on |
| Connection recovery | pass | gestures, scrolling, and side buttons worked after disconnect and reconnect of the active connection |
| Sleep and wake | pass | worker and mouse behavior recovered; gestures, scrolling, and side buttons worked after wake |
| Lifecycle | pass | repeated off/on/status cycles used one worker while running, stopped completely, and removed PID metadata |

The maintainer summarized the checklist as "all worked." No failure was
reported as missed, duplicated, delayed, incorrect, reconnect-only, or
sleep-only. The test did not identify the active connection as Bluetooth or a
specific receiver, and it did not measure active-input CPU or latency.

To reproduce the idle measurement separately, build the release helper first
when needed, then run the command in the controlled-measurement section. Review
the generated summary and raw evidence before recording another result; do not
commit raw machine-local evidence directories.

The only deferred blueprint-derived optimization worth considering is a
development-only comparison of `systemEvents` and `cgEvent` with 0, 2, 5, and
10 ms keypress hold durations.
That experiment is not part of this candidate and does not block documenting
the current result.

## Publication gates

The source is release-engineering ready but is not an official public release.
The repository remains private and has no owner-selected license. Developer ID
credentials, notarization, clean Apple Silicon and Intel Gatekeeper tests,
public visibility, and signed-out release-link checks remain owner actions.

## Safety result

- No timer, polling loop, file watcher, periodic config check, or additional
  persistent worker thread was added.
- Config is generated during development/CI and read once by the worker.
- Scroll events are modified in place and not reposted.
- Synthetic keys are posted only when a gesture consumes an action.
- Debug event formatting is gated; normal recovery output is one concise line.
- Tests and performance scripts are excluded from app and sharing archives.
- User configuration is not migrated or rewritten.

This complete tree now contains the integrated static, idle, and single-device
physical validation record. Isolated branches remain useful evidence, but
should not be merged individually once this candidate is accepted.
