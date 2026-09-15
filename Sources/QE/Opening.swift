import AppKit
import UniformTypeIdentifiers
import QECore

extension BrowserController {
    var associations: FileAssociations { FileAssociations(preferences: preferences) }

    func isDocument(_ file: URL) -> Bool {
        guard let entry = try? FileEntry(url: file.resolvingSymlinksInPath()) else { return false }
        return !entry.isDirectory && !entry.isPackage
    }

    func associatedApplication(for file: URL) -> URL? {
        guard let saved = associations.application(for: file) else { return nil }
        let bundle = Bundle(url: saved.url)
        if FileManager.default.fileExists(atPath: saved.url.path),
           saved.bundleIdentifier == nil || bundle?.bundleIdentifier == saved.bundleIdentifier { return saved.url }
        // Launch Services can find an application moved since the association was saved.
        return saved.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    func openFile(_ file: URL) {
        if isDocument(file), associations.application(for: file) != nil {
            guard let application = associatedApplication(for: file) else {
                chooseApplication(for: file, explanation: "Сохранённое приложение не найдено. Выберите другое.")
                return
            }
            launchDocument(file, with: application, remember: false)
        } else if !NSWorkspace.shared.open(file) {
            if isDocument(file) { chooseApplication(for: file, explanation: "Системное приложение не смогло открыть файл.") }
            else { showError(FileProblem.message("Не удалось открыть \(file.lastPathComponent).")) }
        }
    }

    @objc func openWith(_ sender: Any?) {
        guard selected.count == 1, let file = selected.first, isDocument(file) else { return }
        chooseApplication(for: file)
    }

    @objc func resetAssociation(_ sender: Any?) {
        guard selected.count == 1, let file = selected.first, isDocument(file),
              let ext = FileAssociations.fileExtension(for: file) else { return }
        associations.reset(for: file)
        completionMessage = "Для .\(ext) используется системное приложение"; updateStatus()
    }

    func rememberCheckbox(for file: URL) -> NSButton {
        let ext = FileAssociations.fileExtension(for: file)
        let checkbox = NSButton(checkboxWithTitle: ext.map { "Всегда открывать .\($0) в QE этим приложением" } ?? "У файла нет расширения — только это открытие",
                                target: nil, action: nil)
        checkbox.isEnabled = ext != nil
        checkbox.state = .off
        return checkbox
    }

    func chooseApplication(for file: URL, explanation: String? = nil) {
        var applications = NSWorkspace.shared.urlsForApplications(toOpen: file)
        if let saved = associatedApplication(for: file) {
            applications.removeAll { $0.path == saved.path }
            applications.insert(saved, at: 0)
        }
        guard !applications.isEmpty else { browseApplication(for: file, explanation: explanation); return }
        let alert = NSAlert()
        alert.messageText = "Открыть «\(file.lastPathComponent)» с помощью"
        alert.informativeText = explanation ?? "Выберите приложение для открытия файла."
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26), pullsDown: false)
        picker.setAccessibilityLabel("Приложение")
        let savedPath = associatedApplication(for: file)?.path
        for application in applications {
            let suffix = application.path == savedPath ? " — выбрано в QE" : ""
            // Add NSMenuItems directly: two installed versions may have the same display name.
            let item = NSMenuItem(title: application.deletingPathExtension().lastPathComponent + suffix, action: nil, keyEquivalent: "")
            item.toolTip = application.path
            picker.menu?.addItem(item)
        }
        picker.selectItem(at: 0)
        let checkbox = rememberCheckbox(for: file)
        let content = NSStackView(views: [picker, checkbox])
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 12
        content.frame = NSRect(x: 0, y: 0, width: 420, height: 64)
        picker.widthAnchor.constraint(equalToConstant: 420).isActive = true
        alert.accessoryView = content
        alert.addButton(withTitle: "Открыть"); alert.addButton(withTitle: "Отмена"); alert.addButton(withTitle: "Другое…")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard applications.indices.contains(picker.indexOfSelectedItem) else { return }
            launchDocument(file, with: applications[picker.indexOfSelectedItem], remember: checkbox.state == .on)
        case .alertThirdButtonReturn:
            browseApplication(for: file, remember: checkbox.state == .on, explanation: explanation)
        default: break
        }
    }

    func browseApplication(for file: URL, remember: Bool = false, explanation: String? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Приложение для «\(file.lastPathComponent)»"; panel.prompt = "Открыть"
        panel.message = explanation ?? "Выберите приложение."
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        let checkbox = rememberCheckbox(for: file)
        checkbox.state = remember && checkbox.isEnabled ? .on : .off
        let accessory = inset(checkbox)
        accessory.frame = NSRect(x: 0, y: 0, width: 440, height: 40)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let application = panel.url else { return }
        launchDocument(file, with: application, remember: checkbox.state == .on)
    }

    func launchDocument(_ file: URL, with application: URL, remember: Bool, completion: ((Error?) -> Void)? = nil) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = false // QE presents the error; Gatekeeper still handles its own checks.
        NSWorkspace.shared.open([file], withApplicationAt: application, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { completion?(error); return }
                if let error {
                    if completion == nil { self.showError(FileProblem.message("Не удалось открыть «\(file.lastPathComponent)» в \(application.deletingPathExtension().lastPathComponent).\n\(error.localizedDescription)\nВыберите другое приложение через «Открыть с помощью…».")) }
                } else if remember {
                    self.associations.remember(application, bundleIdentifier: Bundle(url: application)?.bundleIdentifier, for: file)
                    if let ext = FileAssociations.fileExtension(for: file) {
                        self.completionMessage = "Для .\(ext) выбрано \(application.deletingPathExtension().lastPathComponent)"; self.updateStatus()
                    }
                }
                completion?(error)
            }
        }
    }
}
