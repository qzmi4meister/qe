# Releasing QE

Build on Apple Silicon with macOS 26 and Command Line Tools containing the macOS 26 SDK (Swift 6.2+). `VERSION` contains a version such as `0.4.0`; its tag is `v0.4.0`.

## Signing credentials

Import a Developer ID Application certificate and its private key into Keychain. Confirm the identity with `security find-identity -v -p codesigning`. Store the notarization credentials once:

```sh
xcrun notarytool store-credentials QE-notary \
  --key /path/to/AuthKey_KEYID.p8 --key-id KEYID --issuer ISSUER_UUID
```

This example uses an App Store Connect team API key. Set the release environment with the exact certificate name or fingerprint and the Keychain profile:

```sh
export QE_SIGN_IDENTITY='Developer ID Application: NAME (TEAMID)'
export QE_NOTARY_PROFILE=QE-notary
```

Keep private keys and passwords outside the repository. GitHub Actions checks the app without signing credentials; publication runs locally.

## Check and package

1. Update `VERSION` and the documentation, then run `./scripts/check.sh`.
2. Commit the changes, push `main`, and wait for CI to pass.
3. Run `./scripts/release.sh` from a clean checkout of the commit to be tagged.

The script requires both environment variables. It builds separately from `dist/QE.app`, signs with Hardened Runtime and a secure timestamp, waits for Apple to accept the submission, attaches the notarization ticket, and checks the signature and Gatekeeper assessment. Only then does it create:

- `dist/QE-<version>-arm64.zip`: the application, icon, and MIT License.
- `dist/SHA256SUMS`: the archive's SHA-256 checksum.

The script refuses to overwrite an existing ZIP. Never replace a published archive: ship corrections under a new version. To repeat an unpublished build, move the previous ZIP out of `dist` first.

The submission ID and status are saved in `.build/notary-<version>.json`. Retrieve Apple's log using the ID, including after a successful submission to check for warnings:

```sh
xcrun notarytool log SUBMISSION_ID --keychain-profile "$QE_NOTARY_PROFILE"
```

Without `QE_SIGN_IDENTITY`, `./scripts/build.sh` creates an ad-hoc development build. Use `release.sh` for every published archive.

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

Confirm that the release includes both assets and identifies the supported macOS version and architecture. Releases from 0.3.1 onward are signed and notarized; older archives remain unchanged.

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
