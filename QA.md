# QE 0.6.2 verification

Environment: macOS 26.5.1, arm64, Swift 6.3.2. Checked locally on 16.09.2026, including archive cancellation, selection preparation, search scopes, function keys, and split panes. Historical measurements and volume checks are identified separately below.

## Current checks

| Check | Result |
| --- | --- |
| Standalone arm64 application build | Passed |
| Ad-hoc signature verification with `codesign --verify --strict` | Passed |
| 17 file-operation and settings scenarios | No failures in debug and release builds |
| Top-level selection | Duplicates, nested folders, similar prefixes, symbolic links, missing ancestors, root paths, ordering, and cancellation checked; 1,728 additional input combinations matched the previous implementation |
| Extension associations | Persistence, case-insensitive matching, replacement, reset, and exclusion of extensionless files checked |
| Opening with a chosen application | A temporary receiver confirmed one-time opening, saved opening, and automatic opening of a second `.TXT` file; a launch error preserved the saved choice |
| Tabs, navigation, hidden files, search, revealing results, directory updates | No failures |
| Search scopes | Direct-only and recursive results, hidden files, cancellation, query preservation, and exclusion of stale results checked; scope menu works without selection; independent pane settings survive session restoration, splitting, and detaching |
| Independent windows | New Window opens the current folder; menu commands follow the focused window; closing one window preserves the other |
| Moving tabs to windows | Active search and inactive tabs checked; history, selection, sorting, and scroll position preserved |
| Window restoration | Window grouping and active tabs restored; legacy single-window preferences migrated; closed windows removed and last window saved |
| Cross-window Cut/Paste | File moved with contents preserved, using a private test pasteboard |
| Operations and window lifecycle | Detaching disabled during a file operation; Quit blocked when another window has an operation |
| Split panes | Tab context menu splits an inactive or searching tab; history, selection, and sorting preserved; single-tab split creates an independent tab; menu commands follow pane focus |
| Split lifecycle | Both panes and focused pane restored; merging preserves all tabs; closing or detaching the last tab collapses the pane; a busy pane cannot be removed or merged |
| Function keys | F2 renames a fixture; F3 previews the selected file in either pane; F5 copies left to right and F6 moves right to left with content checks; F8 requests Trash confirmation and cancellation preserves the file |
| Folder picker tests | Actual F5/F6 dialogs and their selected destinations checked; the in-process runner completes the modal session directly because `NSSavePanel.ok(_:)` is unimplemented on macOS 26; operations and file contents are still checked end to end |
| Split layout | Window rendered at compact and normal sizes; panes remain usable; active pane distinguished by tab color |
| Parent row (`..`) | Navigation, empty directories, filesystem root, tab switching, and sorting checked; copy, rename, and Trash actions unavailable for the parent row |
| Date and time | Fixed `dd.MM.yyyy HH:mm` format, including a 24-hour afternoon time |
| English interface | Labels, menus, tooltips, errors, fixtures, and scripts translated; the application declares English as its only supported language |
| ZIP and 7z | Creation and extraction with content checks; Unicode, spaces, hidden and empty files, and names containing `-`, `@`, or a newline |
| Archive process cancellation | Normal exit, cooperative SIGTERM, ignored SIGTERM followed by SIGKILL, and a simulated pending SIGKILL checked. The runner returns only after the child exits; the pending explanation is cleared afterward. |
| Cancelling a running extraction | A real `/usr/bin/tar` blocked reading a fixture FIFO was cancelled; source files remained intact, no destination was published, and temporary output was removed. |
| Stalled archive UI | Cancellation preserves the busy operation and explanation; both Quit and window close remain blocked and show that explanation. |
| Opening ZIP archives | Uppercase `.ZIP` opens through QE; extraction uses a free folder name, preserves existing files and archive bytes, and opens the result; later navigation is not interrupted |
| Archives with `..`, absolute paths, or traversal through symbolic links | No writes outside the extraction directory |
| Trash | Temporary file found in Trash with its contents preserved |

## Earlier volume checks

These checks were performed before the first public release on disposable HFS+ disk images. They were not repeated for the interface translation.

| Check | Result |
| --- | --- |
| Moving between volumes | Passed |
| Disk full during a move with replacement | Source and previous destination preserved |
| Writing to a read-only volume | Rejected without removing the source |

## Resource use and responsiveness

One-time 0.6.1 measurements with `swift run -c release QEChecks --benchmark`: preparing a flat selection of 2,000 files took **0.063 seconds**; 10,000 files took **0.534 seconds**. These measurements include deduplication, ancestor filtering, and path sorting, but exclude copying or moving files. They are not guarantees for other disks or directory layouts.

Copy/Move and Trash prepare the selection on a background queue. Cancellation is checked while collecting unique paths and walking ancestors; archive creation uses the same cancellation checks. Trash confirmation appears after preparation and before any deletion. `./scripts/check.sh --benchmark` passed the core and UI checks, including cancelling that confirmation without deleting the selected file.

One-time local measurements of the 0.1.0 baseline, not guarantees for every disk or directory:

- Application size after adding the icon: about **2.1 MiB** (548 KiB before the icon).
- A normal window with one tab: **39 MB physical footprint**, peaking at 41 MB according to the system `footprint` utility.
- RSS for the same process: about **112 MiB**. RSS also includes resident mappings and is not interchangeable with physical footprint.
- Two samples three seconds apart showed **0.0% CPU**, with no increase in accumulated CPU time.
- Reading metadata and sorting **10,000 files took 0.43 seconds** in a debug build.
- In the real-window check with 10,000 files, the first list appeared **0.55 seconds after window setup**. This excludes process startup time.
- During navigation and search in the large directory, the longest gap between scheduled main-thread events was **0.083 seconds**. The measurement used a 0.02-second timer in check mode only.

## Practical limits

- A physical USB drive or external HDD was not disconnected during a write. Volume checks used disposable disk images.
- Archive cancellation allows two seconds after SIGTERM, then sends SIGKILL and allows two more seconds. If the process still has not exited, QE reports the stall and keeps waiting without cleaning its temporary output or releasing the operation. Uninterruptible disk I/O was simulated by withholding SIGKILL in the process-runner check; an actual stuck disk was not induced. macOS Force Quit can leave the child process and temporary output behind.
- Cancelling a single large file can wait for that file's copy to finish. Completed items are not rolled back.
- Password-protected archives, multipart archives, and browsing inside archives are unsupported. Compatibility with every metadata variant from other archivers has not been established.
- UI checks call the real AppKit controllers. A full manual mouse pass, including dragging between applications, has not been completed.
- Local release checks intermittently failed in window focus and F2, and one run timed out in a conflict dialog. A diagnostic rerun passed; the cause is not established. Filename assertions and file-operation checks remain enabled, with more detail on F2 failures.
- During 0.6.2 verification, three full UI runs failed on pane focus/F2 or timed out. A control run of `main`, the isolated stalled-archive UI check, a diagnostic full run, and the final full run without diagnostics passed. The cause of the intermittent failures remains unestablished; no product focus changes were made.
- Published releases through 0.3.0 are signed ad hoc and may require first-launch approval in Privacy & Security. Releases from 0.3.1 use the signing and notarization checks in [RELEASING.md](RELEASING.md).

Run the main checks with `./scripts/check.sh`. Window images and the machine-readable report are in `.build/ui-check/`; historical large-directory results are in `.build/large-ui-check/`.
