# QE 0.3.0 verification

Environment: macOS 26.5.1, arm64, Swift 6.3.2. Checked on 15.09.2026. Historical measurements and volume checks are identified separately below.

## Current checks

| Check | Result |
| --- | --- |
| Standalone arm64 application build | Passed |
| Ad-hoc signature verification with `codesign --verify --strict` | Passed |
| 13 file-operation and settings scenarios | No failures |
| Extension associations | Persistence, case-insensitive matching, replacement, reset, and exclusion of extensionless files checked |
| Opening with a chosen application | A temporary receiver confirmed one-time opening, saved opening, and automatic opening of a second `.TXT` file; a launch error preserved the saved choice |
| Tabs, navigation, hidden files, search, revealing results, directory updates | No failures |
| Parent row (`..`) | Navigation, empty directories, filesystem root, tab switching, and sorting checked; copy, rename, and Trash actions unavailable for the parent row |
| Date and time | Fixed `dd.MM.yyyy HH:mm` format, including a 24-hour afternoon time |
| English interface | Labels, menus, tooltips, errors, fixtures, and scripts translated; the application declares English as its only supported language |
| ZIP and 7z | Creation and extraction with content checks; Unicode, spaces, hidden and empty files, and names containing `-`, `@`, or a newline |
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
- Cancelling a single large file can wait for that file's copy to finish. Completed items are not rolled back.
- Password-protected archives, multipart archives, and browsing inside archives are unsupported. Compatibility with every metadata variant from other archivers has not been established.
- UI checks call the real AppKit controllers. A full manual mouse pass, including dragging between applications, has not been completed.
- Releases are signed ad hoc and are not notarized by Apple. macOS may require first-launch approval in Privacy & Security.

Run the main checks with `./scripts/check.sh`. Window images and the machine-readable report are in `.build/ui-check/`; historical large-directory results are in `.build/large-ui-check/`.
