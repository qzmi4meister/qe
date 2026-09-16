import AppKit
import QuickLookUI
import QECore

extension UICheck {
    func selectFixture(_ name: String, in pane: BrowserController) {
        guard let index = pane.entries.firstIndex(where: { $0.name == name }) else {
            failures.append("Missing fixture: \(name)"); return
        }
        pane.table.selectRowIndexes(IndexSet(integer: pane.row(forEntry: index)), byExtendingSelection: false)
        expect(pane.selected.first?.lastPathComponent == name, "Could not select fixture: \(name)")
    }

    func pressFunctionKey(_ number: Int, in pane: BrowserController) {
        pane.window?.makeKeyAndOrderFront(nil)
        pane.window?.makeFirstResponder(pane.table)
        let key = String(UnicodeScalar(0xF703 + number)!)
        let codes: [Int: UInt16] = [2: 120, 3: 99, 5: 96, 6: 97, 8: 100]
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .function,
            timestamp: 0, windowNumber: pane.window!.windowNumber, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: codes[number]!)!
        expect(NSApp.mainMenu!.performKeyEquivalent(with: event), "F\(number) did not invoke its menu action; selected=\(pane.selected) responder=\(String(describing: pane.window?.firstResponder))")
    }

    func functionKeyModal(_ number: Int, in pane: BrowserController, inspect: @escaping (NSWindow) -> Void) {
        let timer = Timer(timeInterval: 0.3, repeats: false) { _ in
            guard let modal = NSApp.modalWindow else {
                self.failures.append("F\(number) did not open a dialog"); NSApp.abortModal(); return
            }
            inspect(modal)
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        pressFunctionKey(number, in: pane)
        timer.invalidate()
    }

    func confirmDirectory(_ picker: NSOpenPanel) {
        // NSSavePanel.ok(_:) is unimplemented on macOS 26. Complete its modal session
        // with the actual selected URL; keep the checks on destination and file contents.
        expect(picker.url?.resolvingSymlinksInPath() == picker.directoryURL?.resolvingSymlinksInPath(),
               "Folder picker did not select the intended destination")
        NSApp.stopModal(withCode: .OK)
    }

    func checkSplit(_ directory: URL) {
        browser.newTab(nil)
        browser.navigate(directory.appendingPathComponent("Projects"))
        waitUntil({ !self.browser.isLoading }) {
            self.selectFixture("needle.txt", in: self.browser)
            self.browser.captureTab()
            let tab = self.browser.tabs[self.browser.active]
            self.browser.selectTab(0)
            self.waitUntil({ !self.browser.isLoading }) {
                let button = self.browser.tabsStack.arrangedSubviews[1] as! TabButton
                guard let item = button.menu?.items.first(where: { $0.action == #selector(BrowserController.splitTab(_:)) }) else {
                    self.failures.append("Split missing from tab context menu"); self.finish(); return
                }
                NSApp.sendAction(item.action!, to: item.target, from: item)
                guard let right = self.browser.otherPane, let owner = self.browser.owner else {
                    self.failures.append("Split did not create another pane"); self.finish(); return
                }
                self.waitUntil({ !right.isLoading }) {
                    self.expect(self.browser.appDelegate?.windows.count == 1 && owner.panes.count == 2, "Split opened another window")
                    self.expect(right.tabs[0].id == tab.id && right.tabs[0].history == tab.history && right.tabs[0].selection == tab.selection, "Split lost tab state")
                    self.expect(right.selected.first?.lastPathComponent == "needle.txt", "Split lost selected file")
                    self.expect(self.browser.tabs.count == 1 && self.browser.current == directory, "Split moved the wrong tab")
                    self.expect(right.sortKey == self.browser.sortKey && right.ascending == self.browser.ascending, "Split lost sorting")
                    self.expect(!right.validateMenuItem(item), "Nested split is enabled")
                    self.expect(NSApp.target(forAction: #selector(BrowserController.newTab(_:))) as? BrowserController === right, "Menu does not target right pane")
                    NSApp.sendAction(#selector(BrowserController.newTab(_:)), to: nil, from: nil)
                    self.expect(right.tabs.count == 2 && self.browser.tabs.count == 1, "New Tab used wrong pane")
                    right.closeCurrentTab(nil)
                    self.browser.window?.makeFirstResponder(self.browser.table)
                    self.expect(owner.activePane === self.browser, "Pane focus did not follow first responder")
                    self.expect(NSApp.target(forAction: #selector(BrowserController.copyTo(_:))) as? BrowserController === self.browser, "Menu does not target left pane")
                    self.browser.window?.setContentSize(NSSize(width: 780, height: 560))
                    owner.splitController.view.layoutSubtreeIfNeeded()
                    self.expect(owner.panes.allSatisfy { $0.scroll.bounds.width >= 380 && $0.scroll.bounds.height > 150 }, "Split panes are too small")
                    self.saveSplitImage("split-small.png")
                    self.browser.window?.setContentSize(NSSize(width: 1060, height: 680))
                    right.navigate(directory.appendingPathComponent("Photos"))
                    self.waitUntil({ !right.isLoading }) { self.checkFunctionKeys(right, directory: directory) }
                }
            }
        }
    }

    func checkFunctionKeys(_ right: BrowserController, directory: URL) {
        let source = directory.appendingPathComponent("shortcut-source.txt")
        let renamed = directory.appendingPathComponent("shortcut-renamed.txt")
        do { try Data("shortcut contents".utf8).write(to: source) }
        catch { failures.append(error.localizedDescription); finish(); return }
        browser.reload()
        waitUntil({ !self.browser.isLoading }) {
            self.selectFixture(source.lastPathComponent, in: self.browser)
            self.functionKeyModal(2, in: self.browser) { modal in
                let field = modal.contentView.flatMap { self.views(in: $0).compactMap { $0 as? NSTextField }.first { $0.isEditable } }
                self.expect(field?.stringValue == source.lastPathComponent, "F2 did not use selected filename")
                field?.currentEditor()?.string = renamed.lastPathComponent
                field?.stringValue = renamed.lastPathComponent
                modal.makeFirstResponder(nil)
                NSApp.stopModal(withCode: .alertFirstButtonReturn)
            }
            self.waitUntil({ self.browser.operation == nil && !self.browser.isLoading }) {
                self.expect(!FileManager.default.fileExists(atPath: source.path) && FileManager.default.fileExists(atPath: renamed.path), "F2 did not rename fixture")
                self.selectFixture(renamed.lastPathComponent, in: self.browser)
                self.pressFunctionKey(3, in: self.browser)
                self.waitUntil({ QLPreviewPanel.shared()?.isVisible == true }) {
                    let panel = QLPreviewPanel.shared()!
                    self.expect(panel.currentController as? BrowserController === self.browser, "F3 preview belongs to wrong pane")
                    self.expect(panel.currentPreviewItem?.previewItemURL?.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path, "F3 previews wrong file")
                    panel.orderOut(nil)
                    self.functionKeyModal(5, in: self.browser) { modal in
                        guard let picker = modal as? NSOpenPanel else {
                            self.failures.append("F5 did not open folder picker"); NSApp.abortModal(); return
                        }
                        self.expect(picker.directoryURL?.resolvingSymlinksInPath() == right.current.resolvingSymlinksInPath(), "F5 destination is not the opposite pane")
                        self.confirmDirectory(picker)
                    }
                    self.waitUntil({ self.browser.operation == nil && !self.browser.isLoading }) {
                        let copy = right.current.appendingPathComponent(renamed.lastPathComponent)
                        self.expect((try? Data(contentsOf: copy)) == Data("shortcut contents".utf8), "F5 did not copy into opposite pane")
                        self.expect(FileManager.default.fileExists(atPath: renamed.path), "F5 removed the source")
                        self.checkMoveKey(right, directory: directory)
                    }
                }
            }
        }
    }

    func checkMoveKey(_ right: BrowserController, directory: URL) {
        let source = right.current.appendingPathComponent("shortcut-move.txt")
        let moved = directory.appendingPathComponent(source.lastPathComponent)
        do { try Data("move contents".utf8).write(to: source) }
        catch { failures.append(error.localizedDescription); finish(); return }
        right.reload()
        waitUntil({ !right.isLoading }) {
            self.selectFixture(source.lastPathComponent, in: right)
            self.pressFunctionKey(3, in: right)
            let preview = QLPreviewPanel.shared()!
            self.expect(preview.currentController as? BrowserController === right &&
                        preview.currentPreviewItem?.previewItemURL?.resolvingSymlinksInPath() == source.resolvingSymlinksInPath(),
                        "Quick Look did not follow the right pane")
            preview.orderOut(nil)
            self.functionKeyModal(6, in: right) { modal in
                guard let picker = modal as? NSOpenPanel else {
                    self.failures.append("F6 did not open folder picker"); NSApp.abortModal(); return
                }
                self.expect(picker.directoryURL?.resolvingSymlinksInPath() == directory.resolvingSymlinksInPath(), "F6 destination is not the opposite pane")
                self.confirmDirectory(picker)
            }
            self.waitUntil({ right.operation == nil && !right.isLoading }) {
                self.expect(!FileManager.default.fileExists(atPath: source.path) && (try? Data(contentsOf: moved)) == Data("move contents".utf8), "F6 did not move from right to left: \(right.completionMessage ?? "no result"), target=\(moved.path), contents=\((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])")
                self.browser.reload()
                self.waitUntil({ !self.browser.isLoading }) {
                    self.selectFixture(moved.lastPathComponent, in: self.browser)
                    self.functionKeyModal(8, in: self.browser) { modal in
                        self.expect(modal.contentView.map { self.text(in: $0).contains("Move 1 item(s) to Trash?") } == true, "F8 skipped Trash confirmation")
                        NSApp.abortModal()
                    }
                    self.expect(FileManager.default.fileExists(atPath: moved.path), "Cancelling F8 removed a file")
                    self.saveSplitImage("split.png")
                    self.checkSplitLifecycle(right, directory: directory)
                }
            }
        }
    }

    func views(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views(in: $0) } }

    func text(in view: NSView) -> [String] {
        ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap { text(in: $0) }
    }

    func saveSplitImage(_ name: String) {
        guard let view = browser.window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name))
            }
        } catch { failures.append(error.localizedDescription) }
    }

    func checkSplitLifecycle(_ right: BrowserController, directory: URL) {
        let app = browser.appDelegate!
        let owner = browser.owner!
        for pane in owner.panes {
            pane.window?.makeFirstResponder(pane.table)
            pane.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            for action in [#selector(BrowserController.renameSelected(_:)), #selector(BrowserController.previewSelected(_:)), #selector(BrowserController.copyTo(_:)), #selector(BrowserController.moveTo(_:)), #selector(BrowserController.trashSelected(_:))] {
                expect(!pane.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: "")), "Function key enabled for parent row")
            }
        }
        selectFixture("shortcut-renamed.txt", in: right)
        right.window?.makeFirstResponder(right.pathField)
        expect(owner.activePane === right, "Path editor did not activate its pane")
        expect(!right.validateMenuItem(NSMenuItem(title: "", action: #selector(BrowserController.trashSelected(_:)), keyEquivalent: "")), "Trash enabled in path editor")
        right.window?.makeFirstResponder(right.table)
        right.operation = Cancellation()
        browser.closeSplit(nil)
        right.closeCurrentTab(nil)
        expect(owner.panes.count == 2, "Closed a pane during its file operation")
        let dismiss = Timer(timeInterval: 0.1, repeats: false) { _ in NSApp.abortModal() }
        RunLoop.main.add(dismiss, forMode: .modalPanel)
        expect(!owner.windowShouldClose(browser.window!), "Window close ignored operation in right pane")
        dismiss.invalidate()
        right.operation = nil
        app.saveWindows()
        let restored = AppDelegate()
        let restoreSuite = suite + ".split-restore"
        restored.preferences = UserDefaults(suiteName: restoreSuite)!
        restored.preferences.set(browser.preferences.array(forKey: "windows"), forKey: "windows")
        restored.restoreWindows()
        expect(restored.windows.count == 1 && restored.browsers.count == 2, "Split session did not restore")
        expect(restored.browsers.map { $0.tabs.map(\.url) } == owner.panes.map { $0.tabs.map(\.url) }, "Split session lost tabs")
        expect(restored.windows.first?.focusedPane == 1, "Split session lost active pane")
        for window in restored.windows { window.window?.performClose(nil) }
        restored.preferences.removePersistentDomain(forName: restoreSuite)
        browser.window?.makeKeyAndOrderFront(nil)
        let ids = Set(owner.panes.flatMap { $0.tabs.map(\.id) })
        browser.closeSplit(nil)
        expect(owner.panes.count == 1 && Set(browser.tabs.map(\.id)) == ids, "Close Split lost tabs")
        expect(right.owner == nil && right.watcher == nil && right.search == nil, "Closed pane retained background work")
        browser.selectTab(1)
        browser.navigate(directory)
        browser.searchField.stringValue = "needle"
        browser.startSearch(nil)
        waitUntil({ self.browser.search == nil }) {
            self.browser.splitTab(nil)
            guard let searchPane = self.browser.otherPane else { self.failures.append("Could not split search tab"); self.finish(); return }
            self.waitUntil({ searchPane.search == nil && !self.browser.isLoading }) {
                self.expect(searchPane.isSearch && searchPane.searchField.stringValue == "needle" && searchPane.entries.count == 1, "Split lost active search")
                searchPane.closeCurrentTab(nil)
                self.expect(owner.panes.count == 1 && self.browser.tabs.count == 1, "Closing last pane tab did not collapse split")
                self.browser.splitTab(nil)
                guard let duplicate = self.browser.otherPane else { self.failures.append("Single tab cannot split"); self.finish(); return }
                self.expect(duplicate.current == self.browser.current && duplicate.tabs[0].id != self.browser.tabs[0].id, "Single-tab split did not create independent tab")
                duplicate.moveTabToWindow(nil)
                self.expect(owner.panes.count == 1 && app.windows.count == 2, "Detaching last pane tab did not collapse split")
                app.windows.last?.window?.performClose(nil)
                self.browser.window?.makeKeyAndOrderFront(nil)
                self.browser.window?.makeFirstResponder(self.browser.table)
                self.waitUntil({ !self.browser.isLoading }) { self.checkArchiveOpening(directory) }
            }
        }
    }
}
