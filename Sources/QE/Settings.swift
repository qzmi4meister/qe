import AppKit
import UniformTypeIdentifiers
import QECore

final class FolderDefaults {
    static let bundleID = "local.qe.files"
    static let previousKey = "previousFolderApplication"
    let preferences: UserDefaults
    let applicationURL: URL
    let currentApplication: () -> URL?
    let applicationForID: (String) -> URL?
    let setApplication: (URL, @escaping (Error?) -> Void) -> Void
    private(set) var isChanging = false

    init(preferences: UserDefaults, applicationURL: URL = Bundle.main.bundleURL,
         currentApplication: @escaping () -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: .folder) },
         applicationForID: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
         setApplication: @escaping (URL, @escaping (Error?) -> Void) -> Void = { url, completion in
             NSWorkspace.shared.setDefaultApplication(at: url, toOpen: .folder) { error in
                 DispatchQueue.main.async { completion(error) }
             }
         }) {
        self.preferences = preferences; self.applicationURL = applicationURL
        self.currentApplication = currentApplication; self.applicationForID = applicationForID
        self.setApplication = setApplication
    }
    var isEnabled: Bool { currentApplication().flatMap { Bundle(url: $0)?.bundleIdentifier } == Self.bundleID }

    func setEnabled(_ enabled: Bool, completion: @escaping (Error?) -> Void) {
        guard !isChanging else { return }
        guard enabled != isEnabled else { completion(nil); return }
        let previousID = currentApplication().flatMap { Bundle(url: $0)?.bundleIdentifier } ?? "com.apple.finder"
        let restoreID = preferences.string(forKey: Self.previousKey) ?? "com.apple.finder"
        let target = enabled ? applicationURL :
            (restoreID == Self.bundleID ? nil : applicationForID(restoreID)) ?? applicationForID("com.apple.finder")
        guard let target, Bundle(url: target)?.bundleIdentifier != nil,
              !enabled || Bundle(url: target)?.bundleIdentifier == Self.bundleID else {
            completion(FileProblem.message(enabled ? "Open the installed QE.app to change this setting." : "The previous application and Finder could not be found."))
            return
        }
        // Persist before macOS asks for consent so quitting cannot lose the restore target.
        let savedID = preferences.string(forKey: Self.previousKey)
        if enabled { preferences.set(previousID, forKey: Self.previousKey) }
        isChanging = true
        setApplication(target) { error in
            self.isChanging = false
            let matches = self.currentApplication().flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle(url: target)?.bundleIdentifier
            let failure = error ?? (matches ? nil : FileProblem.message("macOS did not change the default application for folders. Please try again."))
            if let failure {
                if enabled && !self.isEnabled {
                    if let savedID { self.preferences.set(savedID, forKey: Self.previousKey) }
                    else { self.preferences.removeObject(forKey: Self.previousKey) }
                }
                completion(failure); return
            }
            if !enabled { self.preferences.removeObject(forKey: Self.previousKey) }
            completion(nil)
        }
    }
}

final class SettingsController: NSWindowController, NSWindowDelegate {
    let folderDefaults: FolderDefaults
    let defaultFolders = NSButton(checkboxWithTitle: "Open folders in QE by default", target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "")

    init(folderDefaults: FolderDefaults) {
        self.folderDefaults = folderDefaults
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 205),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "QE Settings"; window.delegate = self; window.tabbingMode = .disallowed
        defaultFolders.target = self; defaultFolders.action = #selector(changeDefaultFolders(_:))
        let explanation = NSTextField(wrappingLabelWithString:
            "Open folders from Terminal and other apps in QE. Turning this off restores your previous app, or Finder if it is no longer available.")
        explanation.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [defaultFolders, explanation, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func showWindow(_ sender: Any?) { refresh(); super.showWindow(sender); window?.makeKeyAndOrderFront(sender) }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }
    func refresh() {
        defaultFolders.state = folderDefaults.isEnabled ? .on : .off
        defaultFolders.isEnabled = !folderDefaults.isChanging
        let name = folderDefaults.currentApplication().map { FileManager.default.displayName(atPath: $0.path) } ?? "Unknown"
        status.stringValue = folderDefaults.isChanging ? "Waiting for macOS…" : "Currently opens folders: \(name)"
    }
    @objc func changeDefaultFolders(_ sender: Any?) {
        let enabled = defaultFolders.state == .on
        folderDefaults.setEnabled(enabled) { [weak self] error in
            guard let self else { return }
            self.refresh()
            if let error {
                let alert = NSAlert()
                alert.messageText = "Could Not Change Default Application"
                alert.informativeText = error.localizedDescription
                if let window = self.window { alert.beginSheetModal(for: window) }
            }
        }
        refresh()
    }
}
