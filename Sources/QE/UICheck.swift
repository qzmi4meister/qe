#if DEBUG
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
        // Modal panels need to service main-queue callbacks from AppKit's remote view service.
        // Enter checks from the run loop, rather than keeping a main-queue block on the stack.
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
            self.waitUntil(condition, then: action, attempts: attempts - 1)
        }
    }
    func start() {
        retained = self
        BrowserController.clipboard = NSPasteboard.withUniqueName()
        let pulse = DispatchSource.makeTimerSource(queue: .main)
        pulse.schedule(deadline: .now(), repeating: .milliseconds(20))
        pulse.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            self.longestMainThreadGap = max(self.longestMainThreadGap, now.timeIntervalSince(self.lastPulse))
            self.lastPulse = now
        }
        pulse.resume(); self.pulse = pulse
        if CommandLine.arguments.contains("--sidebar-check") {
            checkSidebarFolders { self.finish() }
            return
        }
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
            self.waitUntil({ !self.browser.isLoading }) { self.checkSearchScope(directory) }
        }
    }
    func chooseSearchScope(_ recursive: Bool, in pane: BrowserController) {
        guard let item = pane.searchField.searchMenuTemplate?.items.first(where: { $0.tag == (recursive ? 1 : 0) }) else {
            failures.append("Search scope menu item is missing"); return
        }
        expect(pane.validateMenuItem(item), "Search scope is disabled without a selected file")
        NSApp.sendAction(item.action!, to: item.target, from: item)
        expect(pane.searchIncludesSubfolders == recursive, "Search scope command targeted another pane")
        expect(pane.searchField.searchMenuTemplate?.items.filter { $0.state == .on }.map(\.tag) == [recursive ? 1 : 0], "Search scope checkmark is incorrect")
    }
    func checkSearchFocus() {
        let generation = browser.generation
        let results = browser.entries.map(\.url)
        let selection = browser.selected
        let search = browser.search
        browser.owner!.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: browser.window))
        expect(browser.generation == generation && browser.search === search, "Window activation restarted the search")
        expect(browser.entries.map(\.url) == results && browser.selected == selection, "Window activation lost search results or selection")
        if let search { expect(!search.isCancelled, "Window activation cancelled the running search") }
    }
    func checkSearchScope(_ directory: URL) {
        let direct = directory.appendingPathComponent("needle-local.txt")
        do { try Data("scope fixture".utf8).write(to: direct) }
        catch { failures.append(error.localizedDescription); finish(); return }
        expect(browser.searchIncludesSubfolders, "Search must include subfolders by default")
        browser.table.deselectAll(nil)
        browser.searchField.stringValue = "needle"
        browser.startSearch(nil)
        checkSearchFocus()
        let previousSearch = browser.search!
        browser.refresh(nil)
        expect(previousSearch.isCancelled && browser.search !== previousSearch, "Explicit Refresh did not restart the search")
        let refreshedSearch = browser.search!
        chooseSearchScope(false, in: browser)
        expect(refreshedSearch.isCancelled, "Scope change did not cancel previous search")
        waitUntil({ self.browser.search == nil }) {
            self.expect(self.browser.entries.map(\.name) == ["needle-local.txt"], "This Folder included descendants or stale recursive results")
            self.expect(self.browser.searchField.stringValue == "needle", "Scope change cleared the search query")
            self.expect(self.browser.table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("parent"))?.isHidden == true, "This Folder shows a redundant parent column")
            self.browser.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            self.checkSearchFocus()
            self.chooseSearchScope(true, in: self.browser)
            self.waitUntil({ self.browser.search == nil }) {
                self.expect(Set(self.browser.entries.map(\.name)) == Set(["needle-local.txt", "needle.txt"]), "Recursive search was not restarted")
                self.expect(self.browser.table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("parent"))?.isHidden == false, "Recursive search hides result folders")
                do { try FileManager.default.removeItem(at: direct) }
                catch { self.failures.append(error.localizedDescription) }
                self.browser.leaveSearch(); self.browser.reload()
                self.waitUntil({ !self.browser.isLoading }) { self.checkWindows(directory) }
            }
        }
    }
    func checkWindows(_ directory: URL) {
        guard let app = browser.appDelegate else { failures.append("Missing window owner"); finish(); return }
        browser.window?.setContentSize(NSSize(width: 1024, height: 642))
        do {
            for index in 0..<60 {
                try Data().write(to: directory.appendingPathComponent("Projects/window-\(index).txt"))
            }
        } catch { failures.append(error.localizedDescription); finish(); return }
        browser.newTab(nil)
        browser.navigate(directory.appendingPathComponent("Projects"))
        waitUntil({ !self.browser.isLoading }) {
            guard let index = self.browser.entries.firstIndex(where: { $0.name == "needle.txt" }) else {
                self.failures.append("Window fixture missing"); self.finish(); return
            }
            let file = self.browser.entries[index].url
            self.browser.table.selectRowIndexes(IndexSet(integer: self.browser.row(forEntry: index)), byExtendingSelection: false)
            if let row = self.browser.table.selectedRowIndexes.first { self.browser.table.scrollRowToVisible(row) }
            self.browser.selectTab(0)
            self.waitUntil({ !self.browser.isLoading }) {
                let tab = self.browser.tabs[1]
                let button = self.browser.tabsStack.arrangedSubviews[1] as! TabButton
                guard let item = button.menu?.items.first else { self.failures.append("Tab menu missing"); self.finish(); return }
                self.expect(self.browser.validateMenuItem(item), "Move inactive tab is disabled")
                NSApp.sendAction(item.action!, to: item.target, from: item)
                guard let other = app.browsers.last, other !== self.browser else { self.failures.append("Tab did not create window"); self.finish(); return }
                self.waitUntil({ !other.isLoading }) {
                    self.expect(app.browsers.count == 2 && self.browser.tabs.count == 1, "Tab was copied instead of moved")
                    self.expect(other.tabs[0].id == tab.id && other.tabs[0].history == tab.history && other.tabs[0].position == tab.position, "Tab history was lost")
                    self.expect(other.selected.map(\.path) == [file.path], "Moved tab lost selection: saved=\(tab.selection), actual=\(other.selected.map(\.path))")
                    self.expect(other.sortKey == self.browser.sortKey && other.ascending == self.browser.ascending, "Moved tab lost sorting")
                    let clip = other.scroll.contentView
                    var requested = clip.bounds
                    requested.origin.y = tab.scroll - (other.table.headerView?.frame.height ?? 0)
                    let expectedY = clip.constrainBoundsRect(requested).origin.y
                    self.expect(tab.scroll > 0 && other.tabs[0].scroll == tab.scroll && abs(clip.bounds.origin.y - expectedY) < 1,
                                "Moved tab lost scroll position: saved=\(tab.scroll), expected=\(expectedY), actual=\(clip.bounds.origin.y)")
                    self.expect(self.browser.current == directory, "Moving inactive tab changed source directory")
                    self.expect(!other.validateMenuItem(item), "Single tab can be detached")
                    self.expect(NSApp.target(forAction: #selector(BrowserController.newTab(_:))) as? BrowserController === other, "Menu does not target new window")
                    NSApp.sendAction(#selector(BrowserController.newTab(_:)), to: nil, from: nil)
                    self.expect(other.tabs.count == 2 && self.browser.tabs.count == 1, "Menu changed wrong window")
                    self.browser.window?.makeKeyAndOrderFront(nil)
                    NSApp.sendAction(#selector(BrowserController.newTab(_:)), to: nil, from: nil)
                    self.expect(self.browser.tabs.count == 2 && other.tabs.count == 2, "Menu did not follow window focus")
                    self.browser.closeCurrentTab(nil)
                    other.window?.performClose(nil)
                    self.expect(app.browsers.count == 1 && self.browser.window?.isVisible == true, "Closing window affected another window")
                    self.waitUntil({ !self.browser.isLoading }) { self.checkSearchWindow(directory) }
                }
            }
        }
    }
    func checkSearchWindow(_ directory: URL) {
        let app = browser.appDelegate!
        browser.newTab(nil)
        browser.searchField.stringValue = "needle"
        browser.startSearch(nil)
        waitUntil({ self.browser.search == nil }) {
            self.browser.moveTabToWindow(nil)
            let other = app.browsers.last!
            self.waitUntil({ other.search == nil && !self.browser.isLoading }) {
                self.expect(other !== self.browser && other.isSearch && other.searchField.stringValue == "needle", "Moving active tab lost search")
                self.expect(other.entries.first?.name == "needle.txt", "Moved search results missing")
                self.expect(self.browser.tabs.count == 1 && !self.browser.isSearch, "Source search not cleared")
                other.window?.performClose(nil)
                self.browser.window?.makeKeyAndOrderFront(nil)
                NSApp.sendAction(#selector(BrowserController.newWindow(_:)), to: nil, from: nil)
                let destination = app.browsers.last!
                self.expect(app.browsers.count == 2 && destination.current == directory, "New Window did not open current folder")
                destination.navigate(directory.appendingPathComponent("Photos"))
                self.waitUntil({ !destination.isLoading }) { self.checkWindowTransfer(destination, directory: directory) }
            }
        }
    }
    func checkWindowTransfer(_ destination: BrowserController, directory: URL) {
        let source = directory.resolvingSymlinksInPath().appendingPathComponent("cross-window.txt")
        do { try Data("window transfer".utf8).write(to: source) }
        catch { failures.append(error.localizedDescription); finish(); return }
        browser.reload()
        waitUntil({ !self.browser.isLoading }) {
            guard let index = self.browser.entries.firstIndex(where: { $0.name == source.lastPathComponent }) else {
                self.failures.append("Move fixture missing"); self.finish(); return
            }
            let file = self.browser.entries[index].url
            self.browser.table.selectRowIndexes(IndexSet(integer: self.browser.row(forEntry: index)), byExtendingSelection: false)
            self.browser.window?.makeFirstResponder(self.browser.table)
            self.browser.cutFiles(nil)
            self.expect(BrowserController.cutURLs == [file], "Cut did not select fixture")
            self.expect(destination.clipboardURLs() == [file], "Pasteboard does not contain cut file")
            destination.pasteFiles(nil)
            self.expect(destination.operation != nil, "Paste did not start operation; responder=\(String(describing: destination.window?.firstResponder))")
            self.waitUntil({ destination.operation == nil && !destination.isLoading }) {
                self.expect(!FileManager.default.fileExists(atPath: source.path), "Cut between windows copied instead of moving")
                self.expect((try? Data(contentsOf: destination.current.appendingPathComponent(source.lastPathComponent))) == Data("window transfer".utf8), "Cross-window move lost contents")
                self.checkWindowRestoration(destination)
            }
        }
    }
    func checkWindowRestoration(_ other: BrowserController) {
        let app = browser.appDelegate!
        other.newTab(nil)
        app.saveWindows()
        let saved = browser.preferences.array(forKey: "windows") as! [[String: Any]]
        expect(saved.count == 2, "Window persistence overwrote another window")
        let restoreSuite = suite + ".restore"
        let restored = AppDelegate()
        restored.preferences = UserDefaults(suiteName: restoreSuite)!
        restored.preferences.set(saved, forKey: "windows")
        restored.restoreWindows()
        expect(restored.browsers.map { $0.tabs.map(\.url) } == app.browsers.map { $0.tabs.map(\.url) }, "Restored window tabs differ")
        expect(restored.browsers.map(\.active) == app.browsers.map(\.active), "Restored active tabs differ")
        for window in restored.browsers { window.window?.performClose(nil) }
        expect(restored.browsers.isEmpty, "Closed windows remain retained")
        expect(restored.preferences.array(forKey: "windows")?.count == 1, "Last window not saved for reopening")
        restored.preferences.removePersistentDomain(forName: restoreSuite)
        restored.preferences.set([browser.current.path, other.current.path], forKey: "tabs")
        restored.preferences.set(1, forKey: "activeTab")
        restored.restoreWindows()
        expect(restored.browsers.count == 1 && restored.browsers[0].tabs.count == 2 && restored.browsers[0].active == 1, "Legacy tabs did not migrate")
        expect(restored.browsers.allSatisfy(\.searchIncludesSubfolders), "Legacy sessions lost recursive search default")
        for window in restored.browsers { window.window?.performClose(nil) }
        restored.preferences.removePersistentDomain(forName: restoreSuite)

        other.operation = Cancellation()
        let move = NSMenuItem(title: "", action: #selector(BrowserController.moveTabToWindow(_:)), keyEquivalent: "")
        other.newTab(nil)
        expect(!other.validateMenuItem(move), "Busy window allows detaching tab")
        let dismiss = Timer(timeInterval: 0.1, repeats: false) { _ in NSApp.abortModal() }
        RunLoop.main.add(dismiss, forMode: .modalPanel)
        browser.window?.makeKeyAndOrderFront(nil)
        expect(app.applicationShouldTerminate(NSApp) == .terminateCancel, "Quit ignored an operation in another window")
        dismiss.invalidate()
        other.operation = nil
        other.window?.performClose(nil)
        expect(app.browsers.count == 1 && browser.preferences.array(forKey: "windows")?.count == 1, "Closed window remains in session")
        browser.window?.makeKeyAndOrderFront(nil)
        waitUntil({ !self.browser.isLoading }) { self.checkSplit(self.browser.current) }
    }
    func checkArchiveOpening(_ directory: URL) {
        let archive = directory.appendingPathComponent("sample.ZIP")
        let existing = directory.appendingPathComponent("sample")
        let source = directory.appendingPathComponent("Notes.md")
        do {
            try Archives.create([source], at: archive, format: "zip", cancellation: Cancellation())
            try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
            try Data("keep".utf8).write(to: existing.appendingPathComponent("keep.txt"))
        } catch { failures.append(error.localizedDescription); finish(); return }
        let archiveData = try? Data(contentsOf: archive)
        browser.reload()
        waitUntil({ !self.browser.isLoading }) {
            guard let row = self.browser.entries.firstIndex(where: { $0.name == archive.lastPathComponent }) else {
                self.failures.append("Archive fixture missing"); self.finish(); return
            }
            self.browser.table.selectRowIndexes(IndexSet(integer: self.browser.row(forEntry: row)), byExtendingSelection: false)
            self.browser.openSelected(nil)
            self.expect(self.browser.operation != nil, "ZIP was not opened by QE")
            self.waitUntil({ self.browser.operation == nil && !self.browser.isLoading }) {
                self.expect(self.browser.current.lastPathComponent == "sample (2)", "Extracted directory did not open in QE")
                self.expect((try? Data(contentsOf: self.browser.current.appendingPathComponent("Notes.md"))) == (try? Data(contentsOf: source)), "Extracted contents differ")
                self.expect((try? Data(contentsOf: existing.appendingPathComponent("keep.txt"))) == Data("keep".utf8), "Extraction overwrote existing folder")
                self.expect((try? Data(contentsOf: archive)) == archiveData, "Opening modified archive")
                self.browser.history(-1)
                self.waitUntil({ !self.browser.isLoading }) {
                    self.expect(self.browser.current == directory, "Back from extracted folder failed")
                    self.browser.openFile(archive)
                    let photos = directory.appendingPathComponent("Photos").standardizedFileURL
                    self.browser.navigate(photos)
                    self.waitUntil({ self.browser.operation == nil && !self.browser.isLoading }) {
                        self.expect(self.browser.current == photos, "Extraction interrupted later navigation")
                        self.expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sample (3)/Notes.md").path), "Repeated extraction failed")
                        self.browser.navigate(directory)
                        self.waitUntil({ !self.browser.isLoading }) { self.checkOpening() }
                    }
                }
            }
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
            self.waitUntil({ received().contains(file.resolvingSymlinksInPath().path) }) {
                self.browser.launchDocument(file, with: application, remember: true) { error in
                    self.expect(error == nil, "Remembered opening failed: \(String(describing: error))")
                    self.expect(FileAssociations(preferences: UserDefaults(suiteName: self.suite)!).application(for: file)?.url.path == application.path, "Association was not persisted")
                    let second = self.browser.current.appendingPathComponent("another.TXT")
                    do { try Data("fixture".utf8).write(to: second) }
                    catch { self.failures.append(error.localizedDescription); self.finish(); return }
                    self.browser.reload()
                    self.waitUntil({ !self.browser.isLoading }) {
                        self.selectFixture(second.lastPathComponent, in: self.browser)
                        self.browser.window?.makeKeyAndOrderFront(nil)
                        self.browser.window?.makeFirstResponder(self.browser.table)
                        self.pressKey("\r", code: 36, in: self.browser)
                    }
                    self.waitUntil({ received().contains(second.resolvingSymlinksInPath().path) && received().filter { $0 == file.resolvingSymlinksInPath().path }.count >= 2 }) {
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
                                self.checkStalledArchiveClosing()
                                self.checkSidebarFolders { self.finish() }
                            }
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
    func checkStalledArchiveClosing() {
        let app = browser.appDelegate!
        let other = app.openWindow(tabs: [BrowserTab(browser.current)])
        other.operation = Cancellation()
        let pending = "The archiver has not stopped. Temporary files are being kept."
        other.operation?.cancel(); other.operation?.setPendingMessage(pending)
        other.cancelCurrent()
        expect(other.status.stringValue == pending && other.operation != nil, "Stalled cancellation lost its operation or explanation")
        for quit in [true, false] {
            let closeAlert = Timer(timeInterval: 0.1, repeats: false) { _ in
                let content = NSApp.modalWindow?.contentView
                self.expect(content.map { self.text(in: $0).contains(pending) } == true, "Stalled archive explanation missing from close/quit dialog")
                NSApp.abortModal()
            }
            RunLoop.main.add(closeAlert, forMode: .modalPanel)
            if quit { expect(app.applicationShouldTerminate(NSApp) == .terminateCancel, "Quit released a stalled archive") }
            else { expect(!other.owner!.windowShouldClose(other.window!), "Window close released a stalled archive") }
            closeAlert.invalidate()
        }
        other.operation = nil
        other.window?.performClose(nil)
    }
    func finish() {
        pulse?.cancel()
        BrowserController.clipboard.releaseGlobally()
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
#endif
