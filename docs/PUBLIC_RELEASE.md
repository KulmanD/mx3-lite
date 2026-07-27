# Public release guide

This guide prepares mx3-lite for public distribution without changing the
worker's runtime behavior. Release work does not add automatic startup,
telemetry, an updater, network access, or background logging.

## Owner-controlled prerequisites

Complete these before publishing the first release:

1. Choose and add a `LICENSE`. No license is selected automatically because
   the repository owner must decide how others may use and redistribute the
   source.
2. Confirm the repository is public and set a concise description and topics.
   Recommended topics: `macos`, `swift`, `logitech`, `mx-master`, `mouse`, and
   `accessibility`.
3. Obtain an Apple Developer Program membership, a **Developer ID
   Application** certificate, and notarization credentials.
4. Confirm the release page and every asset can be opened in a private browser
   window while signed out of GitHub.

Do not publish ad-hoc signed validation artifacts as official downloads.

## Build validation archives

The default command builds separate Apple Silicon and Intel archives. Separate
artifacts avoid installing an unused architecture slice and keep disk usage
lower than a universal binary.

```bash
bash scripts/package-release.sh
```

Build one architecture while iterating:

```bash
bash scripts/package-release.sh --arch arm64
bash scripts/package-release.sh --arch x86_64
```

Artifacts and `CHECKSUMS.txt` are written under:

```text
dist/releases/v<VERSION>/
```

Validation archives are ad-hoc signed. They verify compilation, exact
architecture, bundle structure, extraction, signatures, checksums, privacy
exclusions, and absence of test-framework linkage.

## Sign and notarize

List available signing identities:

```bash
security find-identity -v -p codesigning
```

Store notarization credentials in the login keychain once. Replace the sample
values with the owner's Apple account, team ID, and app-specific password:

```bash
xcrun notarytool store-credentials mx3-lite-notary \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Create both public artifacts:

```bash
APP_VERSION=0.3.0 \
DEVELOPER_ID_APPLICATION="Developer ID Application: OWNER (TEAMID)" \
NOTARYTOOL_PROFILE="mx3-lite-notary" \
bash scripts/package-release.sh
```

The script signs the helper, settings executable, and app with hardened
runtime; submits each architecture archive to Apple; staples the accepted
ticket; rebuilds the ZIP; runs Gatekeeper validation; and writes final
checksums. Credentials are read from the keychain and are never copied into the
project or archive.

## Publish checklist

- [ ] A deliberate `LICENSE` is present
- [ ] Repository description, topics, and visibility are correct
- [ ] Both archives are Developer ID signed, notarized, and stapled
- [ ] `CHECKSUMS.txt` verifies with `shasum -a 256 -c CHECKSUMS.txt`
- [ ] `arm64` archive is tested on an Apple Silicon Mac
- [ ] `x86_64` archive is tested on an Intel Mac
- [ ] Fresh extraction and first launch pass on each architecture
- [ ] Accessibility and Input Monitoring permission flow is clear
- [ ] Start, quit settings, Status, Stop, and stale-PID behavior pass
- [ ] `Stop` leaves no `mx3-lite` process
- [ ] No network socket or normal log appears while the worker is running
- [ ] Release assets work in a signed-out private browser window
- [ ] Source and app archives contain no user config, personal path, build
      cache, certificate, key, or notarization credential

## Runtime and architecture

The helper and settings app remain separate native Swift executables. Each
published ZIP contains only one architecture, so only that architecture is
installed and loaded. Packaging and notarization do not add runtime threads,
timers, wakeups, or network behavior to the worker.
