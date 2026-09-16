import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var browsers: [BrowserController] = []
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
                    active: Int = 0, frame: String? = nil) -> BrowserController {
        let previous = NSApp.keyWindow ?? browsers.last?.window
        let browser = BrowserController(tabs: tabs, active: active, preferences: preferences)
        browser.appDelegate = self
        browsers.append(browser)
        if let frame, let window = browser.window {
            let rect = NSRectFromString(frame)
            if rect.width >= 780 && rect.height >= 450 {
                window.setFrame(window.constrainFrameRect(rect, to: window.screen), display: false)
            }
        } else if let previous {
            browser.window?.cascadeTopLeft(from: NSPoint(x: previous.frame.minX + 24, y: previous.frame.maxY - 24))
        }
        browser.showWindow(nil)
        browser.window?.makeFirstResponder(browser.table)
        saveWindows()
        return browser
    }
    func restoreWindows(startURL: URL? = nil) {
        if let startURL { openWindow(tabs: [BrowserTab(startURL)]); return }
        if let saved = preferences.array(forKey: "windows") as? [[String: Any]], !saved.isEmpty {
            for state in saved {
                guard let paths = state["tabs"] as? [String], !paths.isEmpty else { continue }
                openWindow(tabs: paths.map { BrowserTab(URL(fileURLWithPath: $0)) },
                           active: state["activeTab"] as? Int ?? 0, frame: state["frame"] as? String)
            }
        } else if let paths = preferences.stringArray(forKey: "tabs"), !paths.isEmpty {
            openWindow(tabs: paths.map { BrowserTab(URL(fileURLWithPath: $0)) },
                       active: preferences.integer(forKey: "activeTab"))
        }
        if browsers.isEmpty { openWindow() }
    }
    func saveWindows() {
        guard !browsers.isEmpty else { return }
        preferences.set(browsers.map { browser -> [String: Any] in
            ["tabs": browser.tabs.map { $0.url.path }, "activeTab": browser.active,
             "frame": NSStringFromRect(browser.window!.frame)]
        }, forKey: "windows")
    }
    func closedWindow(_ browser: BrowserController) {
        if browsers.count == 1 { saveWindows() }
        browsers.removeAll { $0 === browser }
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
