import AppKit
import QECore

/// Run against a disposable fixture directory: QE --directory <fixture> --ui-check <output>.
/// Exercises the real controller and renders its view without accessibility permissions.
final class UICheck {
    let browser: BrowserController
    let output: URL
    let suite: String
    let started = Date()
    var failures: [String] = []
    var firstListSeconds = 0.0
    var longestMainThreadGap = 0.0
    var lastPulse = Date()
    var pulse: DispatchSourceTimer?
    var retained: UICheck?
    init(browser: BrowserController, output: URL, suite: String) {
        self.browser = browser; self.output = output; self.suite = suite
    }
    func expect(_ value: Bool, _ message: String) { if !value { failures.append(message) } }
    func waitUntil(_ condition: @escaping () -> Bool, then action: @escaping () -> Void, attempts: Int = 200) {
        if condition() { action(); return }
        if attempts == 0 { failures.append("Timed out waiting for UI"); finish(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitUntil(condition, then: action, attempts: attempts - 1) }
    }
    func start() {
        retained = self
        let pulse = DispatchSource.makeTimerSource(queue: .main)
        pulse.schedule(deadline: .now(), repeating: .milliseconds(20))
        pulse.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            self.longestMainThreadGap = max(self.longestMainThreadGap, now.timeIntervalSince(self.lastPulse))
            self.lastPulse = now
        }
        pulse.resume(); self.pulse = pulse
        waitUntil({ !self.browser.isLoading }) {
            self.firstListSeconds = Date().timeIntervalSince(self.started)
            let initial = self.browser.current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = self.browser.dateFormatter.timeZone
            let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 21, minute: 5))!
            self.expect(self.browser.dateFormatter.string(from: date) == "15.09.2026 21:05", "Date format must use dd.MM.yyyy and 24-hour time")
            self.expect(self.browser.lastReadError == nil, "Initial directory could not load")
            self.expect(self.browser.entries.contains { $0.name == ".hidden" }, "Hidden files not shown initially")
            self.expect(self.browser.table.frame.width > 400 && self.browser.table.visibleRect.height > 150, "Table layout too small")
            self.expect(self.browser.sidebar.frame.width > 120, "Sidebar has no usable width")
            self.expect(self.browser.pathField.stringValue == initial.path, "Path mismatch: \(self.browser.pathField.stringValue) != \(initial.path)")
            let count = self.browser.entries.count
            self.browser.newTab(nil)
            self.expect(self.browser.tabs.count == 2, "Tab creation failed")
            self.browser.toggleHidden(nil)
            self.waitUntil({ !self.browser.isLoading }) {
                self.expect(self.browser.entries.count < count, "Hidden toggle failed")
                self.browser.toggleHidden(nil)
                self.browser.navigate(initial.appendingPathComponent("Projects"))
                self.waitUntil({ !self.browser.isLoading }) {
                    self.expect(self.browser.entries.contains { $0.name == "needle.txt" }, "Navigation failed")
                    self.browser.history(-1)
                    self.waitUntil({ !self.browser.isLoading }) {
                        self.expect(self.browser.current == initial, "Back navigation failed")
                        self.browser.searchField.stringValue = "needle"
                        self.browser.startSearch(nil)
                        self.waitUntil({ self.browser.search == nil }) {
                            self.expect(self.browser.entries.count == 1 && self.browser.entries.first?.name == "needle.txt", "Search result mismatch")
                            self.browser.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                            self.browser.revealSelected(nil)
                            self.waitUntil({ !self.browser.isLoading }) {
                                self.expect(self.browser.selected.first?.lastPathComponent == "needle.txt", "Reveal selection failed")
                                self.browser.navigate(initial)
                                self.waitUntil({ !self.browser.isLoading }) { self.checkParentNavigation(initial) }
                            }
                        }
                    }
                }
            }
        }
    }
    func checkParentNavigation(_ initial: URL) {
        let table = browser.table
        expect(browser.hasParentRow, "Parent row missing")
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        expect(browser.selected.isEmpty, "Parent row is treated as a file")
        expect(browser.tableView(table, pasteboardWriterForRow: 0) == nil, "Parent row can be dragged as a file")
        for action in [#selector(BrowserController.trashSelected(_:)), #selector(BrowserController.renameSelected(_:)), #selector(BrowserController.copyFiles(_:))] {
            expect(!browser.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: "")), "File operation enabled for parent row")
        }
        browser.selectAllFiles(nil)
        expect(!table.selectedRowIndexes.contains(0) && browser.selected.count == browser.entries.count, "Select all includes parent or misses files")
        if let last = browser.entries.indices.last {
            table.selectRowIndexes(IndexSet(integer: browser.row(forEntry: last)), byExtendingSelection: false)
            let selected = browser.selected
            table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: false)]
            expect(browser.selected == selected, "Sorting changed selected file")
            let cell = browser.tableView(table, viewFor: table.tableColumns[0], row: 0) as? NSTableCellView
            expect(cell?.textField?.stringValue == "..", "Sorting moved parent row")
        }
        browser.navigate(URL(fileURLWithPath: "/"))
        waitUntil({ !self.browser.isLoading }) {
            self.expect(!self.browser.hasParentRow && table.numberOfRows == self.browser.entries.count, "Parent row shown at filesystem root")
            self.browser.navigate(initial.appendingPathComponent("Photos"))
            self.waitUntil({ !self.browser.isLoading }) {
                self.expect(self.browser.entries.isEmpty && table.numberOfRows == 1, "Empty directory has no parent row")
                self.browser.selectTab(0)
                self.waitUntil({ !self.browser.isLoading }) {
                    self.expect(self.browser.current == initial && self.browser.hasParentRow, "First tab navigation changed")
                    self.browser.selectTab(1)
                    self.waitUntil({ !self.browser.isLoading }) {
                        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                        self.browser.openSelected(nil)
                        self.waitUntil({ !self.browser.isLoading }) {
                            self.expect(self.browser.current == initial, "Parent row did not navigate up in second tab")
                            self.checkWatcher(initial)
                        }
                    }
                }
            }
        }
    }
    func checkWatcher(_ directory: URL) {
        do { _ = try Files.create(name: "watcher-check.txt", in: directory, directory: false) }
        catch { failures.append(error.localizedDescription); finish(); return }
        waitUntil({ self.browser.entries.contains { $0.name == "watcher-check.txt" } }) {
            self.browser.closeTab(at: 1)
            self.waitUntil({ !self.browser.isLoading }) { self.checkOpening() }
        }
    }
    func checkOpening() {
        guard let index = CommandLine.arguments.firstIndex(of: "--open-check-app"), CommandLine.arguments.indices.contains(index + 1) else { finish(); return }
        let application = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        guard let fileRow = browser.entries.firstIndex(where: { $0.name == "Shopping List.txt" }) else {
            failures.append("Opening fixture missing in \(browser.current.path): \(browser.entries.map(\.name))"); finish(); return
        }
        let file = browser.entries[fileRow].url
        let log = application.deletingLastPathComponent().appendingPathComponent("opened-files.json")
        let received: () -> [String] = {
            let paths = (try? Data(contentsOf: log)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            return paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        }
        expect(!browser.rememberCheckbox(for: browser.current.appendingPathComponent(".hidden")).isEnabled, "Extensionless file can be associated")
        let menu = NSMenuItem(title: "", action: #selector(BrowserController.openWith(_:)), keyEquivalent: "")
        browser.table.selectRowIndexes(IndexSet(integer: browser.row(forEntry: fileRow)), byExtendingSelection: false)
        expect(browser.validateMenuItem(menu), "Open with unavailable for document")
        browser.launchDocument(file, with: application, remember: false) { error in
            self.expect(error == nil, "One-time opening failed: \(String(describing: error))")
            self.expect(self.browser.associations.application(for: file) == nil, "One-time opening changed association")
            self.browser.launchDocument(file, with: application, remember: true) { error in
                self.expect(error == nil, "Remembered opening failed: \(String(describing: error))")
                self.expect(FileAssociations(preferences: UserDefaults(suiteName: self.suite)!).application(for: file)?.url.path == application.path, "Association was not persisted")
                let second = self.browser.current.appendingPathComponent("another.TXT")
                do { try Data("fixture".utf8).write(to: second) }
                catch { self.failures.append(error.localizedDescription); self.finish(); return }
                self.browser.openFile(second)
                self.waitUntil({ received().contains(second.resolvingSymlinksInPath().path) }) {
                    self.expect(received().filter { $0 == file.resolvingSymlinksInPath().path }.count == 2, "Receiver did not receive both explicit opens")
                    self.browser.launchDocument(file, with: application.deletingLastPathComponent().appendingPathComponent("Missing.app"), remember: true) { error in
                        self.expect(error != nil, "Missing application unexpectedly opened")
                        self.expect(self.browser.associations.application(for: file)?.url.path == application.path, "Failure replaced remembered application")
                        self.waitUntil({ !self.browser.isLoading }) {
                            if let row = self.browser.entries.firstIndex(where: { $0.url.path == file.path }) {
                                self.browser.table.selectRowIndexes(IndexSet(integer: self.browser.row(forEntry: row)), byExtendingSelection: false)
                                self.browser.resetAssociation(nil)
                                self.expect(self.browser.associations.application(for: second) == nil, "Reset did not clear extension association")
                            } else { self.failures.append("Document missing after refresh") }
                            NSApp.activate(ignoringOtherApps: true)
                            self.checkApplicationChooser(file)
                            self.finish()
                        }
                    }
                }
            }
        }
    }
    func checkApplicationChooser(_ file: URL) {
        let timer = Timer(timeInterval: 0.2, repeats: false) { _ in
            guard let view = NSApp.modalWindow?.contentView else {
                self.failures.append("Application chooser was not shown"); NSApp.abortModal(); return
            }
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let controls = descendants(view)
            self.expect(controls.contains { ($0 as? NSPopUpButton)?.numberOfItems ?? 0 > 0 }, "Application list is empty")
            self.expect(controls.contains { ($0 as? NSButton)?.title.hasPrefix("Always open .txt") == true && $0.frame.height > 0 }, "Remember checkbox is missing")
            do {
                try FileManager.default.createDirectory(at: self.output, withIntermediateDirectories: true)
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: self.output.appendingPathComponent("open-with.png"))
                }
            } catch { self.failures.append(error.localizedDescription) }
            NSApp.abortModal()
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        browser.chooseApplication(for: file)
        timer.invalidate()
        expect(browser.associations.application(for: file) == nil, "Cancelling chooser changed association")
    }
    func finish() {
        pulse?.cancel()
        if let index = CommandLine.arguments.firstIndex(of: "--open-check-app"), CommandLine.arguments.indices.contains(index + 1) {
            let path = URL(fileURLWithPath: CommandLine.arguments[index + 1]).resolvingSymlinksInPath().path
            for app in NSWorkspace.shared.runningApplications where app.bundleURL?.resolvingSymlinksInPath().path == path { app.terminate() }
        }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let view = browser.window!.contentView!
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: output.appendingPathComponent("window.png")) }
            } else { failures.append("Could not render window") }
            let report: [String: Any] = ["failures": failures, "seconds": Date().timeIntervalSince(started),
                "firstListSecondsAfterWindowSetup": firstListSeconds,
                "longestMainThreadGapSeconds": longestMainThreadGap,
                "windowWidth": view.bounds.width, "windowHeight": view.bounds.height,
                "tableWidth": browser.table.frame.width, "tableVisibleHeight": browser.table.visibleRect.height,
                "scrollHeight": browser.scroll.frame.height, "rows": browser.entries.count]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("ui-check.json"))
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted), encoding: .utf8)!)
        } catch { failures.append(error.localizedDescription) }
        browser.preferences.removePersistentDomain(forName: suite)
        if CommandLine.arguments.contains("--hold") {
            try? String(browser.window!.windowNumber).write(to: output.appendingPathComponent("window-id"), atomically: true, encoding: .utf8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { exit(self.failures.isEmpty ? 0 : 1) }
        } else { exit(failures.isEmpty ? 0 : 1) }
    }
}
