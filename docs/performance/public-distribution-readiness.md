# Performance report: public distribution readiness

Tracking issue: [#27](https://github.com/KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased/issues/27)

## Decision

- Status: accept the distribution implementation. Public visibility, license
  selection, Developer ID signing, notarization, and hardware launch tests
  remain explicit owner-controlled publication gates.
- Functional benefit: maintainers can produce independently verified Apple
  Silicon and Intel app archives, or use the same path with real Developer ID
  and notarization credentials for public releases.
- Measured cost: zero worker runtime code. `Sources/`, `Package.swift`, and
  `app/Info.plist` are identical to the accepted config-defaults branch.
- Reason: all new work is in release scripts, CI, and documentation. Separate
  single-architecture archives avoid the installed-size cost of a universal
  binary.

## Revisions

| Role | Branch | Commit | Dirty |
| --- | --- | --- | --- |
| Runtime base | `refactor/standardize-config-defaults` | `8ac3154774e0e17a28f9830c6de4336fbc964468` | no |
| Candidate | `release/public-distribution-readiness` | `a812311` | no |

This branch is stacked on #26 because public archives must use the neutral
`config/defaults.json` resource. A tree comparison confirms no runtime source,
package target, or bundle metadata changes after that base.

## Environment

| Item | Value |
| --- | --- |
| Mac | MacBook Pro `Mac16,8` |
| Host architecture | `arm64` |
| macOS | 26.5.1 (25F80) |
| Swift | Apple Swift 6.3.2, Swift 5.9 package mode |
| Local signing | ad-hoc validation only |
| Config SHA-256 | `b25df5cf7b6d9baa14a32efb3ddd883eefa0820ba2e9dbd2218e575c32d1f75a` |

The user config remained byte-for-byte unchanged. No Apple certificate or
notarization credential was available or fabricated.

## Implementation shape

- `scripts/build-release-app.sh` cross-compiles one requested architecture and
  signs the helper, settings executable, and app bundle.
- `scripts/package-release.sh` builds separate `arm64` and `x86_64` archives,
  optionally notarizes and staples them, and writes verified checksums.
- `scripts/verify-release.sh` extracts a fresh archive and checks bundle
  structure, exact architecture, signatures, privacy exclusions, embedded
  user paths, and test-framework linkage.
- CI builds both ad-hoc validation archives independently and uploads them as
  workflow artifacts. It does not publish a GitHub release.
- `docs/PUBLIC_RELEASE.md` documents credentials, signed release commands,
  Gatekeeper verification, publication checks, and owner-controlled blockers.
- The repository description and technical topics were populated. Visibility
  remains private and no license was selected without owner approval.

## Static comparison

| Artifact | Architecture | Executable bytes | Archive bytes |
| --- | --- | ---: | ---: |
| Helper | arm64 | 432840 unsigned / 448496 signed | included below |
| Settings app | arm64 | 755824 unsigned / 769552 signed | 438956 |
| Helper | x86_64 | 442008 unsigned / 463744 signed | included below |
| Settings app | x86_64 | 746568 unsigned / 770704 signed | 450569 |

The Intel and Apple Silicon numbers are not runtime regressions: they are
different instruction sets and code-signature envelopes. Each installed app
contains exactly one architecture. The worker source is unchanged from #26,
and neither helper links `XCTest` or `Testing`.

The lightweight source archive was 81858 bytes and excluded `.build`, `.git`,
`.github`, `dist`, tests, performance probes, user config, retired
machine-specific defaults, and personal paths.

## Verification performed

- [x] `swift build`
- [x] `swift build -c release`
- [x] generated defaults check
- [x] shell syntax checks
- [x] workflow YAML parse
- [x] fresh arm64 archive extraction and verification
- [x] fresh x86_64 archive extraction and verification
- [x] exact architecture checks for both executables in both archives
- [x] nested ad-hoc signature verification
- [x] checksums generated and checked
- [x] source archive privacy/exclusion scan
- [x] Start, Status, Stop lifecycle; no remaining process after Stop
- [x] no worker runtime-source diff from #26
- [ ] GitHub Actions architecture matrix
- [ ] Developer ID signature and Apple notarization with owner credentials
- [ ] Gatekeeper first launch on a clean Apple Silicon Mac
- [ ] Gatekeeper first launch on a clean Intel Mac
- [ ] signed-out release-link verification after publication

Local `swift test` remains unavailable because the selected standalone Command
Line Tools installation does not provide XCTest. GitHub Actions supplies unit
tests and cross-architecture packaging checks.

## Runtime performance

Strict idle and active-event benchmarks were not repeated because the
candidate has no diff under `Sources/`, `Package.swift`, or `app/Info.plist`.
Running the same executable again would measure machine noise rather than a
distribution change. The lifecycle smoke test still stopped the worker
completely, and the existing #26 measurement remains applicable.

## Safety checks

- [x] No worker polling loop, timer, thread, or event-tap change
- [x] No automatic startup, launch agent, or login item
- [x] No updater, telemetry, or app runtime network code
- [x] No normal background logging
- [x] No credentials stored in source or artifacts
- [x] Validation archives clearly identify ad-hoc signing
- [x] Notarization fails closed without a Developer ID identity
- [x] Release checks modify no user config
- [x] Separate architecture archives avoid universal-binary disk overhead

Notarization itself contacts Apple only when a maintainer explicitly provides a
keychain profile to the release script. That deployment action is not linked
into or callable by the app.

## Publication gates

The engineering branch is ready, but an official public release must not be
claimed until the owner:

1. chooses a license or deliberately documents proprietary source terms;
2. changes repository visibility from private when ready;
3. supplies a Developer ID Application identity and notarization profile;
4. completes signed first-launch tests on real Apple Silicon and Intel Macs;
5. verifies release links while signed out of GitHub.

## Interaction result

| Combination | Base | Candidate | Result |
| --- | --- | --- | --- |
| Runtime features | #26 accepted tree | `a812311` | no runtime diff |

No runtime interaction branch is required for distribution-only files.
