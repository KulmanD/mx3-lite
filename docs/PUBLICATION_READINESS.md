# Publication readiness

Audit date: 2026-07-27

Source baseline: `main` at `74d3bee6d9500e4a56f0062ec34b9c36d0443d42`

Runtime measurement commit: `727060fb03ad76d752d413db41bfa5d5132e3dc8`

This report separates source repository publication from future official
binary distribution. It does not change repository visibility, delete releases
or tags, modify GitHub settings, or authorize application binaries.

## Executive status

| Distribution step | Status | Reason |
| --- | --- | --- |
| Keep developing and testing privately | Ready | Source, CI, measurements, physical validation, and packaging evidence are present |
| Publish the source tree | Ready after this documentation branch is merged | The MIT license, security policy, generic configuration naming, and source installation guidance are present |
| Make the GitHub repository public | Pending final manual GitHub actions | Remove the obsolete v0.2.0 and v0.3.0 release entries after explicit confirmation, then enable the selected public security controls and verify the repository while signed out |
| Publish official app binaries | Not ready | Developer ID signing, hardened runtime, notarization, stapling, clean-machine tests, checksums, and public download verification remain incomplete |

## Completed owner decisions

- License: MIT.
- Copyright notice: `Copyright (c) 2026 Denis Kulman`.
- The historical commit email `kulmand@post.bgu.ac.il` is accepted for public
  disclosure.
- Git history will not be rewritten.
- The historical personal configuration filename does not require a history
  rewrite. Its contents were ordinary settings, not a credential.
- Current configuration names must remain generic.
- Obsolete ad-hoc application binaries must not be presented as current or
  official downloads.

## Source repository publication readiness

### Current-tree audit

- No API key, access token, password, private key, certificate, provisioning
  profile, Apple credential, `.env` file, personal home path, phone number,
  personal address, user configuration, tracked build cache, tracked
  `.DS_Store`, log, crash dump, or release binary was found in the tracked tree.
- `.build/`, `dist/`, `DerivedData/`, `.swiftpm/`, and `.DS_Store` are ignored.
- No runtime networking, telemetry, updater, login-item, or launch-agent API was
  identified. Documentation references those terms only to state their absence.
- `Package.swift` declares no external Swift package dependency. Runtime imports
  are Apple system frameworks.
- No vendored third-party source, third-party image, copied license header, or
  acknowledgement requirement was identified.

Pattern and Git-object scans reduce risk but cannot prove that no unknown secret
format exists. Dependabot alerts are enabled. Secret scanning and code scanning
were not enabled at the time of this update.

### License and security policy

- Root `LICENSE` contains the canonical MIT License with the owner-selected
  holder and year.
- Root `SECURITY.md` supports the latest `main` source, rejects public
  vulnerability disclosure, directs future reports to GitHub private
  vulnerability reporting once enabled, and directs ordinary bugs to Issues.
- GitHub should detect the MIT License after this branch is merged into `main`.

### Generic configuration verification

- The editable default configuration is `config/defaults.json`.
- App build scripts copy it as `Contents/Resources/defaults.json`.
- Generated compiled defaults are checked against the same neutral file.
- The runtime user configuration remains
  `~/Library/Application Support/mx3-lite/config.json`.
- Packaging excludes the user-specific runtime configuration.
- No tracked owner home path or active owner-specific configuration filename
  exists.
- Current-tree matches for the retired app resource name are negative CI checks
  that reject it.

Historical commits and tags still contain the retired personal configuration
filename. The owner has accepted that history, so no rewrite is required.

### Existing releases and assets

The release assets were downloaded and re-inspected on 2026-07-27. Their GitHub
digests matched the downloaded files.

| Release | Exact assets | Finding | Recommendation |
| --- | --- | --- | --- |
| `v0.2.0` | `mx3-lite-v0.2.0.zip`; `mx3-lite-v0.2.0.zip.sha256` | The source ZIP contains the retired personal configuration filename and predates the final candidate | Delete the GitHub release entry and both assets; retain tag `v0.2.0` |
| `v0.3.0` | `mx3-lite-app-v0.3.0.zip`; `mx3-lite-app-v0.3.0.zip.sha256`; `mx3-lite-source-v0.3.0.zip`; `mx3-lite-source-v0.3.0.zip.sha256` | The source ZIP contains the retired personal configuration filename; the app ZIP is ad-hoc signed, thin `arm64`, has no Team ID, contains the retired app resource name, and fails Gatekeeper assessment | Delete the GitHub release entry and all four assets; retain tag `v0.3.0` |

The README no longer links to `releases/latest` or presents either release as a
current download. It recommends installation from the current source until an
official signed and notarized release exists.

Deletion is intentionally pending explicit owner confirmation. These commands
delete the release entries and their assets without deleting the Git tags:

```sh
gh release delete v0.2.0 \
  --repo KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased --yes
gh release delete v0.3.0 \
  --repo KulmanD/Mx-Master-3-For-mac-lightweight-swiftBased --yes
```

Do not add `--cleanup-tag`; the `v0.2.0` and `v0.3.0` tags must remain.

### Preserved runtime and packaging evidence

- No Swift runtime source or configuration behavior changes in this publication
  branch.
- The release helper remains 433,528 bytes with a 212,992-byte `__TEXT` segment.
- One controlled 150.086-second idle run recorded zero CPU-time and wakeup
  growth, two stable threads, flat RSS and physical footprint, zero sockets, and
  zero normal-mode log files.
- One MX Master 3S on macOS 26.5.1 passed the maintainer-run gesture, button,
  scrolling, trackpad, reconnect, power-cycle, sleep/wake, and lifecycle matrix.
- Source and app archive scripts exclude user config, tests, performance probes,
  build caches, Git metadata, and personal paths.
- Separate Apple Silicon and Intel validation packages build successfully.
- The source sharing archive includes `LICENSE` after this branch change.

## Remaining manual GitHub actions

Before changing repository visibility:

1. Merge this source-publication PR after all required checks pass.
2. Confirm and delete the obsolete `v0.2.0` and `v0.3.0` release entries using
   the exact commands above. Retain all Git tags.
3. Review the two open Dependabot action-major PRs independently; they are not
   part of this publication change.
4. Review public issues, pull requests, Actions logs, artifacts, tags, and release
   history for presentation context.

At and immediately after the visibility change:

1. Change visibility only through the repository owner's GitHub settings.
2. Enable private vulnerability reporting and confirm the **Report a
   vulnerability** route is visible.
3. Enable secret scanning and push protection where the account plan supports
   them.
4. Enable code scanning if the owner wants an additional automated security
   gate.
5. Confirm GitHub detects the MIT License.
6. Verify README links, badges, source access, issue/report routes, tags, and the
   absence of obsolete release downloads while signed out in a private browser
   window.

Optional presentation work includes adding the `native-app` and `performance`
topics, setting a repository-owned social preview, adding a contribution guide,
and adding issue and pull request templates.

## Current GitHub control snapshot

| Control | State on 2026-07-27 | Publication action |
| --- | --- | --- |
| Repository visibility | Private | Change manually only after the pre-publication checklist is complete |
| Main protection | Active `Protect main` ruleset; pull request required; deletion and non-fast-forward updates blocked; `swift`, `release-archives (arm64)`, and `release-archives (x86_64)` required | Keep |
| Dependabot version updates | Controlled weekly configuration for GitHub Actions and Swift packages | Keep |
| Dependabot alerts | Enabled; no open alerts observed | Keep |
| Secret scanning | Disabled | Enable at publication where supported |
| Code scanning | Disabled | Enable if desired as an additional gate |
| Private vulnerability reporting | Not enabled | Enable when the repository becomes public |
| Actions token permissions | Read-only by default | Keep |
| Actions runtime | `actions/checkout@v4` and `actions/upload-artifact@v4` remain on `main`; major-update PRs #43 and #42 are open with passing CI | Review separately from this PR |

## Future official binary distribution readiness

Official application binaries remain blocked on all of the following:

1. Apple Developer Program membership.
2. A Developer ID Application certificate.
3. Final Apple Silicon and Intel builds from the selected release commit.
4. Developer ID signing of the helper, settings executable, and app with the
   hardened runtime.
5. Apple notarization of the final archives.
6. Stapling and validation of the notarization ticket.
7. Gatekeeper verification from fresh archive extractions.
8. Clean-machine functional testing on Apple Silicon.
9. Clean-machine functional testing on Intel.
10. Final SHA-256 checksum generation and verification.
11. Signed-out download and first-launch verification.

The historical v0.3.0 app ZIP is not a substitute for these steps. No binary
should be published as official until every item is complete.

## Conclusion

After this branch is merged, the current source tree is ready for publication
under the MIT License. The repository must remain private until the obsolete
release entries receive explicit deletion approval and the remaining manual
GitHub publication actions are completed. Official binary distribution remains
separately blocked.
