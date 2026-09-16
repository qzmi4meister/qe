# Build, checks, and releases

Commands run from the repository root. `VERSION` contains the application version.

## Build

The build requires an Apple Silicon Mac with macOS 26 and Apple Command Line Tools containing the macOS 26 SDK and Swift 6.2 or later. The local `dist/QE.app` must be closed before rebuilding.

```sh
./scripts/build.sh
open dist/QE.app
```

The build script creates an ad-hoc development signature unless `QE_SIGN_IDENTITY` is set. Published builds follow the [release procedure](../../../RELEASING.md).

## Checks

```sh
./scripts/check.sh
```

The script builds and runs `QEChecks`, verifies the release credential requirements, and exercises AppKit controllers against temporary files. UI reports and window images are written to `.build/ui-check/`.

Reading and sorting benchmark with 10,000 items:

```sh
./scripts/check.sh --benchmark
```

Additional `.build/debug/QEChecks --volume <path>` checks require a separate empty 32 MiB test volume. The test deliberately writes a 48 MiB file to check disk-full handling. `--readonly-volume <path>` checks write rejection. Normal checks do not create or mount disk images.

[QA.md](../../../QA.md) records dated verification results. Current behavior is defined by the code and described in [README.md](../../../README.md).

## Source layout

- `Sources/QE`: AppKit windows, tabs, menus, background tasks, and UI checks.
- `Sources/QECore`: directory reads, search, file operations, and archives.
- `Tests/QECoreTests`: the standalone `QEChecks` executable.
- `Tests/OpenReceiver`: the receiver application used by file-opening checks.

Archive operations use the system `bsdtar`.

## CI and releases

`.github/workflows/ci.yml` runs the checks and an ad-hoc application build on macOS 26. Signing and notarization run locally with credentials stored in Keychain.

[RELEASING.md](../../../RELEASING.md) defines packaging, GitHub publication, and Homebrew tap updates.
