import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [BrowserWindowController] = []
    var browsers: [BrowserController] { windows.flatMap(\.panes) }
    var preferences = UserDefaults.standard
    var settingsController: SettingsController?
    var didFinishLaunching = false
    var pendingFolderURLs: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let start = arguments.firstIndex(of: "--directory").flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
        #if DEBUG
        let checkIndex = arguments.firstIndex(of: "--ui-check")
        let checkOutput = checkIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let suite = "local.qe.ui-check." + UUID().uuidString
        if checkOutput != nil { preferences = UserDefaults(suiteName: suite)! }
        #endif
        didFinishLaunching = true
        if pendingFolderURLs.isEmpty { restoreWindows(startURL: start) }
        else {
            openFolders(pendingFolderURLs)
            pendingFolderURLs.removeAll()
        }
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        if let checkOutput, let browser = browsers.first {
            UICheck(browser: browser, output: URL(fileURLWithPath: checkOutput), suite: suite).start()
        }
        #endif
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if didFinishLaunching { openFolders(urls) }
        else { pendingFolderURLs.append(contentsOf: urls) }
    }
    func openFolders(_ urls: [URL]) {
        let folders = urls.filter { url in
            guard url.isFileURL else { return false }
            return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.map(\.standardizedFileURL)
        if !folders.isEmpty { openWindow(tabs: folders.map { BrowserTab($0) }) }
        if folders.count != urls.count {
            if browsers.isEmpty { openWindow() }
            let alert = NSAlert()
            alert.messageText = "Could Not Open Folder"
            alert.informativeText = "QE can open existing local or mounted folders. One or more requested locations are unavailable or are not folders."
            alert.runModal()
        }
    }
    @objc func showSettings(_ sender: Any?) {
        if settingsController == nil {
            settingsController = SettingsController(folderDefaults: FolderDefaults(preferences: preferences))
        }
        settingsController?.showWindow(sender)
    }
    @discardableResult
    func openWindow(tabs: [BrowserTab] = [BrowserTab(FileManager.default.homeDirectoryForCurrentUser)],
                    active: Int = 0, frame: String? = nil, rightTabs: [BrowserTab] = [],
                    rightActive: Int = 0, focusedPane: Int = 0,
                    searchIncludesSubfolders: Bool = true, rightSearchIncludesSubfolders: Bool = true) -> BrowserController {
        let previous = NSApp.keyWindow ?? browsers.last?.window
        let controller = BrowserWindowController(tabs: tabs, active: active, preferences: preferences)
        controller.appDelegate = self
        windows.append(controller)
        let browser = controller.panes[0]
        browser.searchIncludesSubfolders = searchIncludesSubfolders
        if !rightTabs.isEmpty {
            let right = BrowserController(tabs: rightTabs, active: rightActive, preferences: preferences)
            right.searchIncludesSubfolders = rightSearchIncludesSubfolders
            controller.addPane(right)
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
                           rightActive: state["rightActiveTab"] as? Int ?? 0, focusedPane: state["focusedPane"] as? Int ?? 0,
                           searchIncludesSubfolders: state["searchIncludesSubfolders"] as? Bool ?? true,
                           rightSearchIncludesSubfolders: state["rightSearchIncludesSubfolders"] as? Bool ?? true)
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
                                       "searchIncludesSubfolders": left.searchIncludesSubfolders,
                                       "frame": NSStringFromRect(controller.window!.frame), "focusedPane": controller.focusedPane]
            if controller.panes.count == 2 {
                let right = controller.panes[1]
                state["rightTabs"] = right.tabs.map { $0.url.path }
                state["rightActiveTab"] = right.active
                state["rightSearchIncludesSubfolders"] = right.searchIncludesSubfolders
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
            browser.showError(QuitProblem(pendingMessage: browser.operation?.pendingMessage))
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
    var pendingMessage: String? = nil
    var errorDescription: String? { pendingMessage ?? "Wait for the operation to finish or cancel it before quitting." }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
