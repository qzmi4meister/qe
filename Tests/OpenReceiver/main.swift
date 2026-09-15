import AppKit

// Disposable receiver used by check.sh; never reads or modifies the opened documents.
final class Receiver: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        let log = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("opened-files.json")
        let previous = (try? Data(contentsOf: log)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        do { try JSONEncoder().encode(previous + urls.map(\.path)).write(to: log, options: .atomic) }
        catch { exit(1) }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let receiver = Receiver()
app.delegate = receiver
app.run()
