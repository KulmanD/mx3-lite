# Performance report: complete feature candidate

This branch composes the accepted config-defaults work, public-distribution
tooling, and all accepted runtime changes. Rejected Issue #22 remains excluded.

## Decision

- Status: implementation and static validation complete; maintainer runtime
  measurements, physical-device checks, and owner publication gates remain.
- Functional result: all accepted issue branches coexist in one buildable,
  packageable source tree.
- Runtime result: exactly the same 433528-byte helper and 212992-byte `__TEXT`
  segment as the optimized runtime-only branch.
- Merge gate: keep this candidate draft until delegated measurements are added.

## Revisions

| Role | Branch | Commit | Helper bytes | `__TEXT` bytes |
| --- | --- | --- | ---: | ---: |
| Frozen baseline | `performance-baseline-v1` | `32dd84159d1feb05b57d9503624d5f8f2704d228` | 432552 | 212992 |
| Runtime-only candidate | `perf/all-runtime-integration` | `96001c8` | 433528 | 212992 |
| Complete candidate | `release/final-feature-candidate` | `b95b7dd` | 433528 | 212992 |

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
| Persistent worker threads | 2 baseline | no new thread in source | pending repeated run |

The standard app and architecture validation archives use the final complete
tree. App-size deltas include the 976-byte helper change, neutral defaults
resource/documentation updates, and code-signature/compression variation.

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
- [ ] GitHub Actions: expected 56 tests plus two architecture jobs
- [ ] Three strict-idle maintainer runs from this complete branch
- [ ] Combined active gesture and scroll workload
- [ ] Physical MX Master and MacBook trackpad validation

## Deferred maintainer command

Run from `release/final-feature-candidate`:

```bash
bash scripts/performance/measure-candidate.sh \
  --label final-feature-candidate
```

Then verify gesture left/right/up, one action per hold, side-button suppression,
missed-release recovery, ratchet and free-spin scrolling, direction reversals,
scroll pauses, trackpad coexistence, and sleep/reconnect behavior.

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

This complete tree is the branch the maintainer should measure. Isolated
branches remain useful evidence, but should not be merged individually once
this candidate is accepted.
