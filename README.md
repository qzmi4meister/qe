# QE

A lightweight native file manager for macOS 26 and Apple Silicon. Independent windows with tabs, a sidebar for folders and disks, and direct access to file operations.

## Install with Homebrew

Requires **macOS 26 or later** and **Apple Silicon (M1 or later)**. The interface is English only.

```sh
brew install --cask qzmi4meister/tap/qe
open -a QE
```

Homebrew installs a prebuilt application. Xcode, Swift, and additional runtime dependencies are not required.

Releases from 0.3.1 onward are signed with Developer ID and notarized by Apple. The notarization ticket is attached to the application.

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
- **Windows** open with **File → New Window**, **⌘⌥N**, or the window button beside **+**. A new window starts in the current folder. Windows and their tab paths are restored at launch.
- **Tabs** open with the **+** button and close with the cross inside each tab. The active tab is blue. Right-click a tab and choose **Move Tab to New Window**, or use the same command in the **Window** menu for the active tab. Moving preserves navigation history, sorting, selection, and scroll position; an active search continues in the new window. The command is available when another tab or pane will remain and no file operation is running in the source pane.
- **Split**: right-click a tab and choose **Split Tab** to show it in a second pane of the same window. With one tab, this creates another tab at the same folder. Each pane has its own tabs, path, search, and selection; click a pane to direct keyboard commands to it. Drag the divider to resize the panes. **Close Split** in the tab context menu combines the tabs into one pane. Closing or detaching a pane’s last tab also removes that pane. Split mode and tab paths are restored at launch.
- **Go Up**: double-click the `..` row at the top of the list. It stays above files when sorting and is excluded from file operations. It is hidden at the filesystem root and in search results.
- **Hidden Files** are shown on first launch. Your choice is saved.
- **Copy / Cut / Paste**, **Copy To… / Move To…**, **Rename**, and **Move to Trash** are in the context menu.
- **Quick Look**: press **F3** or choose **Quick Look** to preview selected files without opening their associated application.
- **Copy To… / Move To…**: **F5 / F6** open a folder picker. In Split, it starts at the other pane’s folder; confirm it or choose another destination.
- **Drag and drop** into a folder or onto a tab copies files. Hold ⌘ to move them.
- **Search**: enter part of a name and press Return. Search includes subfolders; clearing the field returns to the directory listing. **Show in Folder** opens a result's parent folder and selects the item.
- **ZIP / 7z**: double-click an archive to extract it into a folder beside it and open that folder in QE. If the folder already exists, QE chooses a free name. The archive stays intact. **Extract…** lets you choose a destination, and **Open With…** opens the archive in another application. A remembered application choice takes precedence over built-in extraction. Create archives through the context menu.
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
| New window | ⌘⌥N |
| Go to path | ⌘L |
| Search by name | ⌘F |
| Copy path | ⌘⌥C |
| Show hidden files | ⌘⇧. |
| Refresh | ⌘R |
| Open / go up | ⌘↓ / ⌘↑ |
| Rename | F2 or Return |
| Quick Look | F3 |
| Copy to folder | F5 |
| Move to folder | F6 |
| Move to Trash (with confirmation) | F8 or ⌘⌫ |

Depending on your keyboard settings, hold **Fn / 🌐** to use F2–F8 instead of the media and system controls.

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

Checks cover file operations, conflicts, cancellation, source recovery after a failed replacement, Trash, search, ZIP/7z, extraction safety, and extension associations. They also verify that releases require signing and notarization credentials. The application then runs with temporary data to check tabs, independent windows, tab movement, session restoration, split panes, function keys, copying and moving between panes, cross-window Cut/Paste, parent navigation, hidden files, search, selection, and directory updates. Clipboard checks use a private pasteboard. A temporary receiver application verifies one-time opening, saved associations, automatic opening by extension, and preservation of the saved choice after a launch error. Reports and window images are written to `.build/ui-check/`.

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

[RELEASING.md](RELEASING.md) covers signing, notarization, ZIP packaging, publication with `gh`, and Homebrew tap updates. GitHub Actions runs the checks and an ad-hoc application build on macOS 26. Release signing and notarization run locally with credentials stored in Keychain.

## License

[MIT](LICENSE), © 2026 qzmi4meister. The license is also included in the application. Icon provenance is documented in [Resources/README.md](Resources/README.md).
