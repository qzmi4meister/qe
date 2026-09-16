#if DEBUG
import AppKit

extension UICheck {
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
            for (index, key) in keys.enumerated() {
                pressKey(key.0, code: key.1, modifiers: .control, in: pane)
                expect(pane.active == index && owner.activePane === pane, "Control + \(key.0) chose wrong tab or pane")
                expect(pane.otherPane?.active == 0, "Tab shortcut changed the other pane")
            }
            expect(pane.current == directory.appendingPathComponent("Documents"), "Control + 0 did not navigate to tenth tab")
            pane.tabs = original
            pane.active = 0
            pane.rebuildTabs()
            pane.reload()
            pressKey("0", code: 29, modifiers: .control, in: pane)
            expect(pane.active == 0 && pane.tabs.count == 1, "Missing tab shortcut changed tabs")
        }
        browser.focusPath(nil)
        let editor = window.firstResponder
        pressKey("1", code: 18, modifiers: .control, in: browser)
        expect(window.firstResponder === editor, "Current tab shortcut stole editor focus")
        window.makeFirstResponder(browser.table)
        waitUntil({ !self.browser.isLoading && !right.isLoading }) {
            self.browser.searchField.stringValue = "Notes"
            self.browser.startSearch(nil)
            self.waitUntil({ self.browser.search == nil }) {
                self.pressKey("1", code: 18, modifiers: .control, in: self.browser)
                self.pressKey("0", code: 29, modifiers: .control, in: self.browser)
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
