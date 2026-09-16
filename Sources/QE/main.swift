import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [BrowserWindowController] = []
    var browsers: [BrowserController] { windows.flatMap(\.panes) }
    var preferences = UserDefaults.standard
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let start = arguments.firstIndex(of: "--directory").flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
        let checkIndex = arguments.firstIndex(of: "--ui-check")
        let checkOutput = checkIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let suite = "local.qe.ui-check." + UUID().uuidString
        if checkOutput != nil { preferences = UserDefaults(suiteName: suite)! }
        restoreWindows(startURL: start)
        NSApp.activate(ignoringOtherApps: true)
        if let checkOutput, let browser = browsers.first {
            UICheck(browser: browser, output: URL(fileURLWithPath: checkOutput), suite: suite).start()
        }
    }
    @discardableResult
    func openWindow(tabs: [BrowserTab] = [BrowserTab(FileManager.default.homeDirectoryForCurrentUser)],
                    active: Int = 0, frame: String? = nil, rightTabs: [BrowserTab] = [],
                    rightActive: Int = 0, focusedPane: Int = 0) -> BrowserController {
        let previous = NSApp.keyWindow ?? browsers.last?.window
        let controller = BrowserWindowController(tabs: tabs, active: active, preferences: preferences)
        controller.appDelegate = self
        windows.append(controller)
        let browser = controller.panes[0]
        if !rightTabs.isEmpty {
            controller.addPane(BrowserController(tabs: rightTabs, active: rightActive, preferences: preferences))
        }
        if let frame, let window = browser.window {
            let rect = NSRectFromString(frame)
            if rect.width >= 780 && rect.height >= 450 {
                window.setFrame(window.constrainFrameRect(rect, to: window.screen), display: false)
            }
        } else if let previous {
            browser.window?.cascadeTopLeft(from: NSPoint(x: previous.frame.minX + 24, y: previous.frame.maxY - 24))
        }
        browser.showWindow(nil)
        controller.focusedPane = min(max(0, focusedPane), controller.panes.count - 1)
        browser.window?.makeFirstResponder(controller.activePane.table)
        saveWindows()
        return browser
    }
    func restoreWindows(startURL: URL? = nil) {
        if let startURL { openWindow(tabs: [BrowserTab(startURL)]); return }
        if let saved = preferences.array(forKey: "windows") as? [[String: Any]], !saved.isEmpty {
            for state in saved {
                guard let paths = state["tabs"] as? [String], !paths.isEmpty else { continue }
                openWindow(tabs: paths.map { BrowserTab(URL(fileURLWithPath: $0)) },
                           active: state["activeTab"] as? Int ?? 0, frame: state["frame"] as? String,
                           rightTabs: (state["rightTabs"] as? [String] ?? []).map { BrowserTab(URL(fileURLWithPath: $0)) },
                           rightActive: state["rightActiveTab"] as? Int ?? 0, focusedPane: state["focusedPane"] as? Int ?? 0)
            }
        } else if let paths = preferences.stringArray(forKey: "tabs"), !paths.isEmpty {
            openWindow(tabs: paths.map { BrowserTab(URL(fileURLWithPath: $0)) },
                       active: preferences.integer(forKey: "activeTab"))
        }
        if browsers.isEmpty { openWindow() }
    }
    func saveWindows() {
        guard !browsers.isEmpty else { return }
        preferences.set(windows.map { controller -> [String: Any] in
            let left = controller.panes[0]
            var state: [String: Any] = ["tabs": left.tabs.map { $0.url.path }, "activeTab": left.active,
                                       "frame": NSStringFromRect(controller.window!.frame), "focusedPane": controller.focusedPane]
            if controller.panes.count == 2 {
                let right = controller.panes[1]
                state["rightTabs"] = right.tabs.map { $0.url.path }
                state["rightActiveTab"] = right.active
            }
            return state
        }, forKey: "windows")
    }
    func closedWindow(_ controller: BrowserWindowController) {
        if windows.count == 1 { saveWindows() }
        windows.removeAll { $0 === controller }
        saveWindows()
    }
    @objc func newWindow(_ sender: Any?) { openWindow() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let browser = browsers.first(where: { $0.operation != nil }) {
            browser.showWindow(nil)
            browser.showError(QuitProblem())
            return .terminateCancel
        }
        saveWindows()
        return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if browsers.isEmpty { restoreWindows() }
        else if !flag { browsers.last?.showWindow(nil) }
        return true
    }
}

struct QuitProblem: LocalizedError {
    var errorDescription: String? { "Wait for the operation to finish or cancel it before quitting." }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
