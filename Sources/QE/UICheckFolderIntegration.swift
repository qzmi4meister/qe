#if DEBUG
import AppKit
import QECore

extension UICheck {
    func checkFolderIntegration() {
        guard let app = browser.appDelegate,
              let index = CommandLine.arguments.firstIndex(of: "--directory") else {
            failures.append("Folder integration fixture missing"); finish(); return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[index + 1]).standardizedFileURL
        expect(app.windows.count == 1 && browser.current == root.appendingPathComponent("Projects"),
               "Cold open did not open the requested folder without an extra restored window")
        checkFolderDefaults(root)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        let folders = [root.appendingPathComponent("Documents"), root.appendingPathComponent("Папка с пробелами")]
        process.arguments = ["-a", Bundle.main.bundleURL.path] + folders.map(\.path)
        do { try process.run() }
        catch { failures.append(error.localizedDescription); finish(); return }
        waitUntil({ !process.isRunning && app.windows.count == 2 }) {
            self.expect(process.terminationStatus == 0, "open -a failed")
            self.expect(app.windows.last?.activePane.tabs.map(\.url) == folders, "Warm open lost paths or did not group folders in tabs")
            self.expect(self.browser.current == root.appendingPathComponent("Projects"), "Warm open changed the existing window")
            app.windows.last?.window?.performClose(nil)
            let settingsMenu = NSApp.mainMenu?.items.first?.submenu?.items.first { $0.action == #selector(AppDelegate.showSettings(_:)) }
            self.expect(settingsMenu?.keyEquivalent == ",", "Settings keyboard shortcut is missing")
            app.showSettings(nil)
            self.expect(app.settingsController?.window?.isVisible == true, "Settings window did not open")
            if let controller = app.settingsController, let view = controller.window?.contentView {
                view.layoutSubtreeIfNeeded()
                self.expect(view.bounds.contains(controller.status.convert(controller.status.bounds, to: view)), "Settings status is clipped")
                try? FileManager.default.createDirectory(at: self.output, withIntermediateDirectories: true)
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: self.output.appendingPathComponent("settings.png"))
                }
            }
            app.settingsController?.close()
            self.finish()
        }
    }

    func checkFolderDefaults(_ root: URL) {
        do {
            func fixtureApp(_ id: String) throws -> URL {
                let url = root.appendingPathComponent(id + ".app")
                try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL"], format: .xml, options: 0)
                try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
                return url
            }
            let qe = try fixtureApp(FolderDefaults.bundleID)
            let other = try fixtureApp("local.qe.previous-test")
            let finder = try fixtureApp("com.apple.finder")
            var current = other
            var requested: URL?
            var reply: ((Error?) -> Void)?
            var previousExists = true
            let defaults = FolderDefaults(preferences: browser.preferences, applicationURL: qe,
                currentApplication: { current },
                applicationForID: { id in id == "com.apple.finder" ? finder : (previousExists ? other : nil) },
                setApplication: { url, completion in requested = url; reply = completion })
            let key = FolderDefaults.previousKey
            browser.preferences.removeObject(forKey: key)
            var result: Error?
            defaults.setEnabled(true) { result = $0 }
            expect(defaults.isChanging && requested == qe && !defaults.isEnabled, "Enabling must wait for macOS before checking the switch")
            expect(browser.preferences.string(forKey: key) == "local.qe.previous-test", "Pending consent has no persistent restore target")
            reply?(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            expect(result != nil && !defaults.isChanging && !defaults.isEnabled && browser.preferences.string(forKey: key) == nil,
                   "Cancelled default change mutated state or backup")
            defaults.setEnabled(true) { result = $0 }
            current = qe; reply?(nil)
            expect(result == nil && defaults.isEnabled && browser.preferences.string(forKey: key) == "local.qe.previous-test",
                   "Successful enable did not save the previous app")
            defaults.setEnabled(false) { result = $0 }
            expect(requested == other, "Disable did not restore the previous app")
            reply?(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            expect(result != nil && defaults.isEnabled && browser.preferences.string(forKey: key) != nil, "Cancelled restore lost the backup")
            defaults.setEnabled(false) { result = $0 }
            current = other; reply?(nil)
            expect(result == nil && !defaults.isEnabled && browser.preferences.string(forKey: key) == nil, "Restore did not finish cleanly")
            defaults.setEnabled(true) { result = $0 }; reply?(nil)
            expect(result != nil && !defaults.isEnabled && browser.preferences.string(forKey: key) == nil,
                   "A no-op system response was treated as a successful change")
            defaults.setEnabled(true) { result = $0 }; current = qe; reply?(nil)
            previousExists = false
            defaults.setEnabled(false) { result = $0 }
            expect(requested == finder, "Missing previous app did not fall back to Finder")
            current = finder; reply?(nil)
            expect(result == nil && !defaults.isEnabled, "Finder fallback failed")
            requested = nil
            defaults.setEnabled(false) { result = $0 }
            expect(requested == nil, "Disabling an already-disabled setting changed another default")
            let controller = SettingsController(folderDefaults: defaults)
            current = qe; controller.refresh()
            expect(controller.defaultFolders.state == .on, "Settings did not observe an external default change")
            current = other; controller.refresh()
            expect(controller.defaultFolders.state == .off, "Settings kept a stale checkmark")
        } catch { failures.append(error.localizedDescription) }
    }
}
#endif
