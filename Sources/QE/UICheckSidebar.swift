#if DEBUG
import AppKit

extension UICheck {
    func sidebarButton(_ path: String, in pane: BrowserController) -> NSButton? {
        views(in: pane.sidebar).compactMap { $0 as? NSButton }.first { $0.toolTip == path }
    }

    func sidebarModal(_ action: () -> Void, inspect: @escaping (NSWindow) -> Void) {
        let timer = Timer(timeInterval: 0.3, repeats: false) { _ in
            guard let window = NSApp.modalWindow else {
                self.failures.append("Sidebar action did not open a dialog"); NSApp.abortModal(); return
            }
            inspect(window)
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        action()
        timer.invalidate()
    }

    func checkSidebarFolders(completion: @escaping () -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qe-sidebar-" + UUID().uuidString).resolvingSymlinksInPath()
        let folder = root.appendingPathComponent("My Projects — Папка")
        let moved = root.appendingPathComponent("Moved")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("preserve".utf8).write(to: folder.appendingPathComponent("keep.txt"))
        } catch { failures.append(error.localizedDescription); finish(); return }
        let app = browser.appDelegate!
        let other = app.openWindow(tabs: [BrowserTab(folder)])
        let right = BrowserController(tabs: [BrowserTab(browser.current)], preferences: browser.preferences)
        browser.owner!.addPane(right)
        waitUntil({ app.browsers.allSatisfy { !$0.isLoading } }) {
            let add: () -> Void = {
                guard let button = self.views(in: other.sidebar).compactMap({ $0 as? NSButton }).first(where: { $0.toolTip == "Add Folder to Sidebar" }) else {
                    self.failures.append("Add sidebar folder button missing"); return
                }
                button.performClick(nil)
            }
            self.sidebarModal(add) { window in
                self.expect(window is NSOpenPanel, "Add folder did not open a folder picker")
                NSApp.stopModal(withCode: .cancel)
            }
            self.expect(other.sidebarFolderPaths.isEmpty, "Cancelling picker added a link")
            for _ in 0..<2 {
                self.sidebarModal(add) { window in
                    guard let picker = window as? NSOpenPanel else { NSApp.abortModal(); return }
                    self.expect(picker.canChooseDirectories && !picker.canChooseFiles && !picker.allowsMultipleSelection, "Sidebar picker accepts non-folders")
                    self.confirmDirectory(picker, destination: folder)
                }
            }
            self.expect(other.sidebarFolderPaths == [folder.path], "Sidebar did not add exactly one link for duplicate picks")
            self.expect(app.browsers.allSatisfy { self.sidebarButton(folder.path, in: $0) != nil }, "Added link did not reach all windows and Split panes")
            for pane in app.browsers {
                let folderButtons = self.views(in: pane.sidebar).compactMap { $0 as? NSButton }.filter { $0.toolTip?.hasPrefix("/") == true }
                self.expect(Array(folderButtons.prefix(4).map(\.title)) == ["Home", "Applications", "Desktop", "Downloads"], "Built-in folders changed order")
                self.expect(folderButtons.prefix(4).allSatisfy { $0.menu == nil }, "Built-in folder can be removed")
                self.expect(folderButtons.dropFirst(4).first?.toolTip == folder.path, "Custom folder is outside Folders section")
            }
            let restored = BrowserController(tabs: [BrowserTab(root)], preferences: UserDefaults(suiteName: self.suite)!)
            self.expect(self.sidebarButton(folder.path, in: restored) != nil, "Saved link did not restore in a new controller")
            restored.stop()
            self.browser.owner!.removePane(right)
            self.saveSplitImage("sidebar-folders.png")
            other.navigate(root)
            self.waitUntil({ !other.isLoading }) {
                self.sidebarButton(folder.path, in: other)?.performClick(nil)
                self.waitUntil({ !other.isLoading }) {
                    self.expect(other.current.path == folder.path && other.lastReadError == nil, "Custom link did not open folder: \(other.current.path), error=\(String(describing: other.lastReadError))")
                    other.navigate(root)
                    self.waitUntil({ !other.isLoading }) {
                        self.checkSidebarRemoval(other, folder: folder, moved: moved)
                        other.window?.performClose(nil)
                        self.browser.window?.makeKeyAndOrderFront(nil)
                        self.browser.window?.makeFirstResponder(self.browser.table)
                        try? FileManager.default.removeItem(at: root)
                        self.waitUntil({ !self.browser.isLoading }) { completion() }
                    }
                }
            }
        }
    }

    func checkSidebarRemoval(_ pane: BrowserController, folder: URL, moved: URL) {
        let history = pane.tabs[pane.active].history
        let position = pane.tabs[pane.active].position
        func removeFromMenu() {
            guard let button = sidebarButton(folder.path, in: pane),
                  let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: pane.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
                  let menu = button.menu(for: event), let item = menu.items.first else {
                failures.append("Right-click menu missing for custom link"); return
            }
            menu.update()
            expect(item.title == "Remove from Sidebar" && item.isEnabled, "Sidebar removal requires a selected file")
            menu.performActionForItem(at: 0)
        }
        removeFromMenu()
        expect((try? Data(contentsOf: folder.appendingPathComponent("keep.txt"))) == Data("preserve".utf8), "Removing sidebar link deleted folder contents")
        expect(pane.appDelegate!.browsers.allSatisfy { sidebarButton(folder.path, in: $0) == nil }, "Removed link remains in another window")
        pane.saveSidebarFolders([folder.path])
        do { try FileManager.default.moveItem(at: folder, to: moved) }
        catch { failures.append(error.localizedDescription); return }
        for response in [NSApplication.ModalResponse.alertFirstButtonReturn, .alertSecondButtonReturn] {
            sidebarModal({ self.sidebarButton(folder.path, in: pane)?.performClick(nil) }) { window in
                let strings = self.text(in: window.contentView!)
                let buttons = self.views(in: window.contentView!).compactMap { $0 as? NSButton }.map(\.title)
                self.expect(strings.contains("Folder Unavailable") && strings.contains(where: { $0.contains(folder.path) }), "Unavailable-folder dialog lacks explanation or path")
                self.expect(buttons.contains("Cancel") && buttons.contains("Remove from Sidebar"), "Unavailable-folder dialog lacks both choices")
                NSApp.stopModal(withCode: response)
            }
            expect(pane.sidebarFolderPaths == (response == .alertFirstButtonReturn ? [folder.path] : []), "Unavailable-folder choice was not respected")
            expect(pane.tabs[pane.active].history == history && pane.tabs[pane.active].position == position, "Unavailable link changed current folder or history")
        }
        pane.saveSidebarFolders([folder.path])
        removeFromMenu()
        expect(pane.sidebarFolderPaths.isEmpty, "Context menu could not remove unavailable link")
        expect((try? Data(contentsOf: moved.appendingPathComponent("keep.txt"))) == Data("preserve".utf8), "Link removal changed moved folder contents")
        let restored = BrowserController(tabs: [BrowserTab(pane.current)], preferences: UserDefaults(suiteName: suite)!)
        expect(restored.sidebarFolderPaths.isEmpty && sidebarButton(folder.path, in: restored) == nil, "Removed link returned after restoring preferences")
        restored.stop()
        expect(pane.tabs[pane.active].history == history && pane.tabs[pane.active].position == position, "Context removal changed navigation")
    }
}
#endif
