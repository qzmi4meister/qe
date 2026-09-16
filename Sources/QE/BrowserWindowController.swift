import AppKit
import QECore

// The window owns layout and lifetime; each pane keeps its own tabs and file operations.
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    weak var appDelegate: AppDelegate?
    let splitController = NSSplitViewController()
    var focusedPane = 0
    var panes: [BrowserController] { splitController.splitViewItems.compactMap { $0.viewController as? BrowserController } }
    var activePane: BrowserController { panes[min(focusedPane, panes.count - 1)] }

    init(tabs: [BrowserTab], active: Int, preferences: UserDefaults) {
        let window = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.tabbingMode = .disallowed
        splitController.splitView.isVertical = true
        splitController.splitView.dividerStyle = .thin
        window.contentViewController = splitController
        addPane(BrowserController(tabs: tabs, active: active, preferences: preferences))
        window.contentMinSize = NSSize(width: 780, height: 450)
        window.setContentSize(NSSize(width: 1060, height: 680))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func addPane(_ pane: BrowserController) {
        pane.owner = self
        let item = NSSplitViewItem(viewController: pane)
        item.minimumThickness = 390
        splitController.addSplitViewItem(item)
        updateLayout()
    }

    func updateLayout() {
        for pane in panes { pane.setCompact(panes.count == 2); pane.rebuildTabs() }
        splitController.view.layoutSubtreeIfNeeded()
        if panes.count == 2 {
            splitController.splitView.setPosition(splitController.splitView.bounds.width / 2, ofDividerAt: 0)
        }
        updateTitle()
    }

    func focus(_ pane: BrowserController) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        focusedPane = index
        updateTitle()
        pane.updatePreviewController()
        appDelegate?.saveWindows()
    }

    func updateTitle() {
        guard !panes.isEmpty else { return }
        let current = activePane.current
        window?.title = "\(current.lastPathComponent.isEmpty ? "/" : current.lastPathComponent) — QE"
        for pane in panes {
            for button in pane.tabsStack.arrangedSubviews.compactMap({ $0 as? TabButton }) {
                button.focusedPane = pane === activePane
            }
        }
    }

    func removePane(_ pane: BrowserController) {
        guard panes.count == 2, pane.operation == nil,
              let item = splitController.splitViewItems.first(where: { $0.viewController === pane }) else { return }
        pane.stop()
        splitController.removeSplitViewItem(item)
        pane.owner = nil
        focusedPane = 0
        updateLayout()
        window?.makeFirstResponder(activePane.table)
        appDelegate?.saveWindows()
    }

    func closeSplit(keeping pane: BrowserController) {
        guard panes.count == 2, panes.allSatisfy({ $0.operation == nil }),
              let other = panes.first(where: { $0 !== pane }) else { return }
        other.captureTab()
        pane.tabs.append(contentsOf: other.tabs)
        removePane(other)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        for pane in panes {
            pane.hiddenButton.state = pane.shownHidden ? .on : .off
            if !pane.isLoading { pane.refresh(nil) }
        }
    }
    func windowWillClose(_ notification: Notification) {
        panes.forEach { $0.stop() }
        appDelegate?.closedWindow(self)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let busy = panes.first(where: { $0.operation != nil }) {
            busy.showError(FileProblem.message("Wait for the operation to finish or cancel it before closing the window."))
            return false
        }
        return true
    }
}

final class BrowserWindow: NSWindow {
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)
        if result, let owner = windowController as? BrowserWindowController {
            let view = (responder as? NSTextView)?.delegate as? NSView ?? responder as? NSView
            if let view, let pane = owner.panes.first(where: { view.isDescendant(of: $0.view) }) { owner.focus(pane) }
        }
        return result
    }
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown].contains(event.type), let owner = windowController as? BrowserWindowController,
           let pane = owner.panes.first(where: { $0.view.bounds.contains($0.view.convert(event.locationInWindow, from: nil)) }),
           pane !== owner.activePane {
            _ = makeFirstResponder(pane.table)
        }
        super.sendEvent(event)
    }
}

extension BrowserController {
    func tabIndex(for sender: Any?) -> Int? {
        guard let id = (sender as? NSMenuItem)?.representedObject as? UUID else { return active }
        return tabs.firstIndex { $0.id == id }
    }

    @objc func splitTab(_ sender: Any?) {
        guard let owner, owner.panes.count == 1, operation == nil, let index = tabIndex(for: sender) else { return }
        captureTab()
        let query = index == active && isSearch ? searchField.stringValue : nil
        let tab = tabs.count == 1 ? BrowserTab(tabs[index].url) : tabs[index]
        let other = BrowserController(tabs: [tab], preferences: preferences)
        other.table.sortDescriptors = table.sortDescriptors
        // Remove before attaching the second pane so a single-tab source is never closed.
        if tabs.count > 1 { closeTab(at: index) }
        owner.addPane(other)
        if let query { other.searchField.stringValue = query; other.startSearch(nil) }
        window?.makeFirstResponder(other.table)
        appDelegate?.saveWindows()
    }

    @objc func closeSplit(_ sender: Any?) { owner?.closeSplit(keeping: self) }
}
