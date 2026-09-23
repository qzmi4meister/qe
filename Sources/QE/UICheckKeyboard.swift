#if DEBUG
import AppKit

extension UICheck {
    func checkTabRow(_ pane: BrowserController) {
        pane.view.layoutSubtreeIfNeeded()
        let buttons = pane.tabsStack.arrangedSubviews.compactMap { $0 as? TabButton }
        guard let add = views(in: pane.view).compactMap({ $0 as? ActionButton }).first(where: { $0.toolTip == "New Tab" }),
              let first = buttons.first, let last = buttons.last else {
            failures.append("Tab row is missing its buttons"); return
        }
        let addFrame = add.convert(add.bounds, to: pane.view)
        let lastFrame = last.convert(last.bounds, to: pane.view)
        expect(pane.tabsStack.enclosingScrollView == nil, "Tab row scrolls horizontally")
        expect(buttons.count == pane.tabs.count && buttons.allSatisfy { !$0.isHidden && $0.frame.width > 0 }, "Tabs disappeared on overflow")
        expect(buttons.allSatisfy { $0.frame.width <= 175.5 && abs($0.frame.width - first.frame.width) < 1 }, "Tabs do not shrink evenly")
        expect(lastFrame.maxX <= addFrame.minX && abs(addFrame.maxX - (pane.view.bounds.maxX - 12)) < 1, "New Tab is not fixed at the right edge")
        expect(abs(addFrame.midY - lastFrame.midY) < 1, "Tab row buttons shifted vertically")
        expect(buttons.allSatisfy { $0.closeButton.isHidden == ($0.bounds.width < 60) }, "Narrow tab close buttons overlap")
    }

    func pressKey(_ key: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], in pane: BrowserController) {
        let window = pane.window!
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code)!
        window.sendEvent(event)
    }

    func checkKeyboard(_ right: BrowserController, directory: URL) {
        let window = browser.window!
        let owner = browser.owner!
        window.makeFirstResponder(browser.table)
        let selection = browser.table.selectedRowIndexes
        pressKey("\t", code: 48, in: browser)
        expect(owner.activePane === right && window.firstResponder === right.table, "Tab did not focus right pane")
        expect(NSApp.target(forAction: #selector(BrowserController.copyTo(_:))) as? BrowserController === right,
               "Tab did not redirect file commands")
        expect((right.tabsStack.arrangedSubviews.first as? TabButton)?.focusedPane == true &&
               (browser.tabsStack.arrangedSubviews.first as? TabButton)?.focusedPane == false,
               "Tab did not update active pane highlighting")
        pressKey("\t", code: 48, in: right)
        expect(owner.activePane === browser && window.firstResponder === browser.table, "Tab did not return to left pane")
        expect(browser.table.selectedRowIndexes == selection, "Tab lost file selection")
        browser.focusSearch(nil)
        pressKey("\t", code: 48, in: browser)
        expect(owner.activePane === browser, "Tab in search switched panes")

        // Exercise every digit in both panes, with distinct tab IDs and one different path.
        let keys: [(String, UInt16)] = [("1", 18), ("2", 19), ("3", 20), ("4", 21), ("5", 23),
                                      ("6", 22), ("7", 26), ("8", 28), ("9", 25), ("0", 29)]
        for pane in [browser, right] {
            window.makeFirstResponder(pane.table)
            let original = pane.tabs
            pane.tabs += (1...9).map { BrowserTab($0 == 9 ? directory.appendingPathComponent("Documents") : pane.current) }
            pane.rebuildTabs()
            checkTabRow(pane)
            window.setContentSize(NSSize(width: 780, height: 560))
            owner.splitController.view.layoutSubtreeIfNeeded()
            checkTabRow(pane)
            expect(abs(window.contentView!.bounds.width - 780) < 2 && pane.view.bounds.width < 400, "Tab overflow expanded the window or split pane")
            expect((pane.tabsStack.arrangedSubviews.first?.frame.width ?? 175) < 60, "Overflow tabs did not shrink")
            saveSplitImage("tabs-overflow.png")
            window.setContentSize(NSSize(width: 1060, height: 680))
            for (index, key) in keys.enumerated() {
                pressKey(key.0, code: key.1, modifiers: .command, in: pane)
                expect(pane.active == index && owner.activePane === pane, "Command + \(key.0) chose wrong tab or pane")
                expect(pane.otherPane?.active == 0, "Tab shortcut changed the other pane")
            }
            expect(pane.current == directory.appendingPathComponent("Documents"), "Command + 0 did not navigate to tenth tab")
            pane.tabs = original
            pane.active = 0
            pane.rebuildTabs()
            checkTabRow(pane)
            pane.reload()
            pressKey("0", code: 29, modifiers: .command, in: pane)
            expect(pane.active == 0 && pane.tabs.count == 1, "Missing tab shortcut changed tabs")
        }
        browser.focusPath(nil)
        let editor = window.firstResponder
        pressKey("1", code: 18, modifiers: .command, in: browser)
        expect(window.firstResponder === editor, "Current tab shortcut stole editor focus")
        window.makeFirstResponder(browser.table)
        waitUntil({ !self.browser.isLoading && !right.isLoading }) {
            self.browser.searchField.stringValue = "Notes"
            self.browser.startSearch(nil)
            self.waitUntil({ self.browser.search == nil }) {
                self.pressKey("1", code: 18, modifiers: .command, in: self.browser)
                self.pressKey("0", code: 29, modifiers: .command, in: self.browser)
                self.expect(self.browser.isSearch && self.browser.searchField.stringValue == "Notes",
                            "Current or missing tab shortcut cleared search")
                self.browser.navigate(directory)
                self.waitUntil({ !self.browser.isLoading }) {
                    self.browser.table.deselectAll(nil)
                    self.pressKey("\r", code: 36, in: self.browser)
                    self.expect(self.browser.current == directory && NSApp.modalWindow == nil, "Return with no selection changed directory or opened dialog")
                    self.selectFixture("Photos", in: self.browser)
                    self.pressKey("\r", code: 36, modifiers: .capsLock, in: self.browser)
                    self.waitUntil({ !self.browser.isLoading }) {
                        self.expect(self.browser.current == directory.appendingPathComponent("Photos"), "Return did not open selected folder")
                        self.browser.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                        self.pressKey("\u{3}", code: 76, modifiers: .numericPad, in: self.browser)
                        self.waitUntil({ !self.browser.isLoading }) {
                            self.expect(self.browser.current == directory, "Keypad Enter did not open parent row")
                            self.checkFunctionKeys(right, directory: directory)
                        }
                    }
                }
            }
        }
    }
}
#endif
