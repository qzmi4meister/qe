# QE

A lightweight native file manager for macOS 26 and Apple Silicon. One pane with tabs, a sidebar for folders and disks, and direct access to file operations.

## Install with Homebrew

Requires **macOS 26 or later** and **Apple Silicon (M1 or later)**. The interface is English only.

```sh
brew install --cask qzmi4meister/tap/qe
open -a QE
```

Homebrew installs a prebuilt application. Xcode, Swift, and additional runtime dependencies are not required.

The release is signed ad hoc and is not notarized by Apple. If macOS blocks the first launch and you trust this build, try opening it, then go to **System Settings → Privacy & Security → Open Anyway**. See [Apple's instructions](https://support.apple.com/en-us/102445).

Update:

```sh
brew update
brew upgrade --cask qzmi4meister/tap/qe
```

Uninstall:

```sh
brew uninstall --cask qzmi4meister/tap/qe
```

Normal uninstall preserves preferences, saved tabs, and file associations. To remove those as well, use `brew uninstall --cask --zap qzmi4meister/tap/qe`. User files are not removed.

A ZIP for manual installation and `SHA256SUMS` are available in [Releases](https://github.com/qzmi4meister/qe/releases). Extract the ZIP and move `QE.app` to Applications.

## Build from source

Use an Apple Silicon Mac with macOS 26 and Apple Command Line Tools containing the macOS 26 SDK and Swift 6.2 or later. Full Xcode and third-party libraries are not required.

```sh
git clone https://github.com/qzmi4meister/qe.git
cd qe
./scripts/build.sh
open dist/QE.app
```

Quit the local `dist/QE.app` before rebuilding it. The application version is set in `VERSION`.

## Working with files

- **New Folder / New File** are above the file list. New files are empty; enter any valid name and extension.
- **Dates** use `dd.MM.yyyy` and 24-hour `HH:mm` time in your local time zone.
- **Path** is editable at the top of the window. The button beside it copies the current path; the context menu copies paths of selected items.
- **Tabs** open with the **+** button and close with the cross inside each tab. The active tab is blue. Open paths are restored at launch.
- **Go Up**: double-click the `..` row at the top of the list. It stays above files when sorting and is excluded from file operations. It is hidden at the filesystem root and in search results.
- **Hidden Files** are shown on first launch. Your choice is saved.
- **Copy / Cut / Paste**, **Copy To… / Move To…**, **Rename**, and **Move to Trash** are in the context menu.
- **Drag and drop** into a folder or onto a tab copies files. Hold ⌘ to move them.
- **Search**: enter part of a name and press Return. Search includes subfolders; clearing the field returns to the directory listing. **Show in Folder** opens a result's parent folder and selects the item.
- **ZIP / 7z**: create and extract archives through the context menu. Extraction creates a separate folder and preserves the archive.
- **Open With…**: choose an application from the list or click **Other…**. Select **Always open .txt files in QE with this application** to save a choice for that extension. Double-clicking or choosing **Open** then uses that application.
- **Reset Application for .txt** restores the system default for that extension. Associations apply within QE and persist between launches. `.TXT` and `.txt` are equivalent; files without an extension can be opened with an application once.
- **External disks** appear in the sidebar. Removable volumes have an eject button.

When names conflict, choose **Keep Both**, **Skip**, or **Replace**. Replacing a folder replaces it entirely; folders are not merged. Normal deletion sends items to Trash.

### Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New folder | ⌘⇧N |
| New file | ⌘N |
| New / close tab | ⌘T / ⌘W |
| Go to path | ⌘L |
| Search by name | ⌘F |
| Copy path | ⌘⌥C |
| Show hidden files | ⌘⇧. |
| Refresh | ⌘R |
| Open / go up | ⌘↓ / ⌘↑ |
| Rename | Return |
| Move to Trash | ⌘⌫ |

## Limitations

- Copy cancellation is checked between items. A single large file may finish copying first; its temporary copy is then removed.
- Password-protected and multipart archives are not supported. Select items from the same folder when creating an archive.
- Giving an empty file an extension does not create a Word document, spreadsheet, or other structured format.
- Search matches names, does not inspect file contents or application bundles, and does not follow symbolic links.
- There is no general undo. Cancelling an operation leaves completed items in place.

## Checks

```sh
./scripts/check.sh
```

Checks cover file operations, conflicts, cancellation, source recovery after a failed replacement, Trash, search, ZIP/7z, extraction safety, and extension associations. The application then runs with temporary data to check tabs, parent navigation, hidden files, search, selection, and directory updates. A temporary receiver application verifies one-time opening, saved associations, automatic opening by extension, and preservation of the saved choice after a launch error. Reports and window images are written to `.build/ui-check/`.

To measure reading and sorting 10,000 items:

```sh
./scripts/check.sh --benchmark
```

Additional `QEChecks --volume <path>` checks require a separate empty 32 MiB test volume: the test deliberately writes a 48 MiB file to check disk-full handling. `--readonly-volume <path>` checks write rejection. Normal checks do not create or mount disk images.

## Project structure

- `Sources/QE`: AppKit window, tabs, menus, background tasks, and UI checks.
- `Sources/QECore`: directory reads, search, file operations, and archives.
- `Tests/QECoreTests`: a standalone check executable that works with Command Line Tools without XCTest.
- [QA.md](QA.md): verification results and known limits.

Archives use the system `bsdtar`. QE does not invoke a shell, install background services, or build a disk index. English is the only application language; there is no language selector or translation catalog.

## Contributing and releases

Report bugs and suggestions in [GitHub Issues](https://github.com/qzmi4meister/qe/issues). For a file-operation bug, include a minimal example using test data, your macOS version, and the expected result. Run `./scripts/check.sh` before submitting a pull request.

[RELEASING.md](RELEASING.md) covers ZIP packaging, publication with `gh`, and Homebrew tap updates. GitHub Actions runs the checks and release build on macOS 26.

## License

[MIT](LICENSE), © 2026 qzmi4meister. The license is also included in the application. Icon provenance is documented in [Resources/README.md](Resources/README.md).
