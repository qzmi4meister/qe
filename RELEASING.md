# Releasing QE

Build on Apple Silicon with macOS 26 and Command Line Tools containing the macOS 26 SDK (Swift 6.2+). `VERSION` contains a version such as `0.3.0`; its tag is `v0.3.0`.

## Check and package

1. Update `VERSION` and the documentation, then run `./scripts/check.sh`.
2. Commit the changes, push `main`, and wait for CI to pass.
3. Run `./scripts/release.sh` from a clean checkout of the commit to be tagged.

The script builds separately from `dist/QE.app`, verifies the ad-hoc signature, and creates:

- `dist/QE-<version>-arm64.zip`: the application, icon, and MIT License.
- `dist/SHA256SUMS`: the archive's SHA-256 checksum.

The script refuses to overwrite an existing ZIP. Never replace a published archive: ship corrections under a new version. To repeat an unpublished build, move the previous ZIP out of `dist` first.

## Publish with GitHub CLI

Write release notes in `.build/release-notes.md`, then run:

```sh
version=$(cat VERSION)
git tag -a "v$version" -m "QE $version"
git push origin "v$version"
gh release create "v$version" \
  "dist/QE-$version-arm64.zip" dist/SHA256SUMS \
  --verify-tag --draft --title "QE $version" \
  --notes-file .build/release-notes.md
```

Review the draft description and both assets, then publish:

```sh
gh release edit "v$version" --draft=false --latest
```

These builds do not have a Developer ID signature or Apple notarization. State this in the release notes and retain the first-launch instructions in the README. Do not disable Gatekeeper in the installer.

## Update Homebrew

In [qzmi4meister/homebrew-tap](https://github.com/qzmi4meister/homebrew-tap), update `version` and `sha256` in `Casks/qe.rb`. Use the checksum from `dist/SHA256SUMS`; the download URL is derived from the version.

Check the published update:

```sh
brew update
brew audit --cask qzmi4meister/tap/qe
brew fetch --cask qzmi4meister/tap/qe
brew install --cask qzmi4meister/tap/qe
open -a QE
```

If QE is already installed, use `upgrade` instead of `install`. Check the version in **About QE**. The cask requires macOS 26 and Apple Silicon, and the ZIP must contain `QE.app` at its root. Other casks in the tap do not need to change when releasing QE.
