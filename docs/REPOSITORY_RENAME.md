# Repository rename runbook

Canonical repository:

`https://github.com/KulmanD/mx3-lite`

The repository rename is an owner controlled GitHub action. This document does
not rename the repository, change visibility, modify application identifiers, or
publish a release.

## Public repository metadata

Repository name:

`mx3-lite`

Description:

`Lightweight native macOS alternative for Logitech MX Master 3 and 3S gestures and scrolling.`

Topics:

- `macos`
- `swift`
- `logitech`
- `mx-master`
- `mx-master-3`
- `mx-master-3s`
- `mouse`
- `mouse-gestures`
- `scrolling`
- `logi-options`
- `accessibility`
- `native-app`
- `performance`

The README describes mx3-lite as an independent project and does not imply
affiliation with Logitech.

## Owner rename steps

1. Merge the README improvement PR first.
2. Confirm this rename preparation PR is current and all required checks pass.
3. Open the repository on GitHub.
4. Select **Settings > General**.
5. In **Repository name**, enter `mx3-lite` and confirm the rename.
6. Do not change repository visibility during the rename.
7. Set the description and topics listed above.
8. Update the local checkout:

   ```sh
   git remote set-url origin https://github.com/KulmanD/mx3-lite.git
   ```

9. Verify the remote:

   ```sh
   git remote -v
   git ls-remote origin
   ```

10. Merge the rename preparation PR after the renamed repository and its checks
    are healthy.

## Post rename verification

- The new repository page opens at the canonical URL.
- The pre-rename repository URL redirects to the canonical URL.
- `git clone https://github.com/KulmanD/mx3-lite.git` succeeds in a temporary
  directory.
- `git remote -v` shows the canonical fetch and push URL.
- The README test badge loads and links to the Test workflow.
- Existing Actions workflows and run history remain available.
- The active `Protect main` ruleset still targets the default branch and retains
  all required checks.
- `.github/dependabot.yml` remains present and Dependabot can open update pull
  requests.
- `SECURITY.md` appears in the repository Security view.
- Issue and pull request templates are checked; absence is recorded if none are
  intentionally provided.
- The Releases page contains no obsolete downloads.
- The social preview is reviewed and updated if it includes text tied to the
  previous repository name.
- GitHub detects `LICENSE` as MIT.
- Existing issues, pull requests, branches, and tags remain reachable.
- Repository visibility remains unchanged until the separate public launch
  decision.
