import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var browser: BrowserController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let start = arguments.firstIndex(of: "--directory").flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
        let checkIndex = arguments.firstIndex(of: "--ui-check")
        let checkOutput = checkIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let suite = "local.qe.ui-check." + UUID().uuidString
        browser = BrowserController(startURL: start, preferences: checkOutput != nil ? UserDefaults(suiteName: suite)! : .standard)
        browser?.showWindow(nil)
        browser?.window?.makeFirstResponder(browser?.table)
        NSApp.activate(ignoringOtherApps: true)
        if let checkOutput, let browser {
            UICheck(browser: browser, output: URL(fileURLWithPath: checkOutput), suite: suite).start()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if browser?.operation != nil {
            browser?.showError(QuitProblem())
            return .terminateCancel
        }
        browser?.saveTabs()
        return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        browser?.showWindow(nil); return true
    }
}

struct QuitProblem: LocalizedError {
    var errorDescription: String? { "Дождитесь завершения операции или отмените её перед выходом." }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
