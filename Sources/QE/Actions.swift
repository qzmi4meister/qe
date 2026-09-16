import AppKit
import QECore

extension BrowserController {
    func buildMenu() {
        func item(_ title: String, _ action: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers; return item
        }
        if NSApp.mainMenu?.item(withTitle: "File") == nil {
            let bar = NSMenu()
            func menu(_ title: String, _ items: [NSMenuItem]) {
                let root = NSMenuItem(); root.title = title; let menu = NSMenu(title: title)
                items.forEach(menu.addItem); root.submenu = menu; bar.addItem(root)
            }
            let quit = NSMenuItem(title: "Quit QE", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            let about = NSMenuItem(title: "About QE", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            let hide = NSMenuItem(title: "Hide QE", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            menu("QE", [about, .separator(), hide, .separator(), quit])
            menu("File", [item("New Window", #selector(newWindow(_:)), "n", modifiers: [.command, .option]), .separator(),
                item("New Folder", #selector(createFolder(_:)), "n", modifiers: [.command, .shift]),
                item("New File", #selector(createFile(_:)), "n"), .separator(),
                item("New Tab", #selector(newTab(_:)), "t"), item("Close Tab", #selector(closeCurrentTab(_:)), "w"), .separator(),
                item("Open", #selector(openSelected(_:)), "o"), item("Open With…", #selector(openWith(_:))),
                item("Reset Default Application", #selector(resetAssociation(_:))), item("Rename…", #selector(renameSelected(_:)), "\u{F705}", modifiers: []),
                item("Quick Look", #selector(previewSelected(_:)), "\u{F706}", modifiers: []),
                item("Move to Trash", #selector(trashSelected(_:)), "\u{8}"), .separator(),
                item("Create ZIP…", #selector(createZIP(_:))), item("Create 7z…", #selector(create7z(_:))), item("Extract…", #selector(extractArchive(_:)))])
            let trashKey = item("Move to Trash", #selector(trashSelected(_:)), "\u{F70B}", modifiers: [])
            trashKey.isHidden = true; trashKey.allowsKeyEquivalentWhenHidden = true
            bar.items.first { $0.title == "File" }?.submenu?.addItem(trashKey)
            menu("Edit", [item("Cut", #selector(cutFiles(_:)), "x"), item("Copy", #selector(copyFiles(_:)), "c"),
                item("Paste", #selector(pasteFiles(_:)), "v"), item("Select All", #selector(selectAllFiles(_:)), "a"), .separator(),
                item("Copy Path", #selector(copyPaths(_:)), "c", modifiers: [.command, .option]),
                item("Copy To…", #selector(copyTo(_:)), "\u{F708}", modifiers: []),
                item("Move To…", #selector(moveTo(_:)), "\u{F709}", modifiers: [])])
            menu("View", [item("Show Hidden Files", #selector(toggleHidden(_:)), ".", modifiers: [.command, .shift]),
                item("Refresh", #selector(refresh(_:)), "r"), item("Go to Path", #selector(focusPath(_:)), "l"),
                item("Search by Name", #selector(focusSearch(_:)), "f"), item("Show in Folder", #selector(revealSelected(_:)))])
            let windowMenu = NSMenu(title: "Window")
            windowMenu.addItem(item("Move Tab to New Window", #selector(moveTabToWindow(_:))))
            windowMenu.addItem(.separator())
            windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
            let windowItem = NSMenuItem(); windowItem.submenu = windowMenu; bar.addItem(windowItem)
            NSApp.windowsMenu = windowMenu; NSApp.mainMenu = bar
        }

        let context = NSMenu()
        [item("Open", #selector(openSelected(_:))), item("Quick Look", #selector(previewSelected(_:))), item("Open With…", #selector(openWith(_:))),
         item("Reset Default Application", #selector(resetAssociation(_:))), item("Open in New Tab", #selector(openInTab(_:))),
         item("Show in Folder", #selector(revealSelected(_:))), .separator(),
         item("New Folder…", #selector(createFolder(_:))), item("New File…", #selector(createFile(_:))), .separator(),
         item("Copy", #selector(copyFiles(_:))), item("Cut", #selector(cutFiles(_:))), item("Paste", #selector(pasteFiles(_:))),
         item("Copy Path", #selector(copyPaths(_:))), .separator(),
         item("Copy To…", #selector(copyTo(_:))), item("Move To…", #selector(moveTo(_:))), item("Rename…", #selector(renameSelected(_:))),
         .separator(), item("Create ZIP…", #selector(createZIP(_:))), item("Create 7z…", #selector(create7z(_:))),
         item("Extract…", #selector(extractArchive(_:))), .separator(), item("Move to Trash", #selector(trashSelected(_:)))].forEach { $0.target = self; context.addItem($0) }
        table.menu = context
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action
        if action == #selector(toggleHidden(_:)) { menuItem.state = shownHidden ? .on : .off; return true }
        if [#selector(focusPath(_:)), #selector(focusSearch(_:)), #selector(refresh(_:)), #selector(newTab(_:)), #selector(newWindow(_:)), #selector(closeCurrentTab(_:))].contains(action) { return true }
        if action == #selector(splitTab(_:)) {
            return otherPane == nil && operation == nil && tabIndex(for: menuItem) != nil
        }
        if action == #selector(closeSplit(_:)) { return otherPane != nil && owner?.panes.allSatisfy { $0.operation == nil } == true }
        if action == #selector(moveTabToWindow(_:)) {
            let id = menuItem.representedObject as? UUID
            return (tabs.count > 1 || otherPane != nil) && operation == nil && (id == nil || tabs.contains { $0.id == id })
        }
        if action == #selector(copyPaths(_:)) { return true }
        if window?.firstResponder is NSTextView,
           [#selector(cutFiles(_:)), #selector(copyFiles(_:)), #selector(pasteFiles(_:)), #selector(selectAllFiles(_:))].contains(action) { return true }
        if action == #selector(selectAllFiles(_:)) { return !entries.isEmpty }
        if window?.firstResponder is NSTextView,
           [#selector(renameSelected(_:)), #selector(previewSelected(_:)), #selector(copyTo(_:)), #selector(moveTo(_:)), #selector(trashSelected(_:))].contains(action) { return false }
        if action == #selector(previewSelected(_:)) { return !selected.isEmpty }
        if action == #selector(openSelected(_:)) { return parentSelected || !selected.isEmpty }
        if action == #selector(copyFiles(_:)) { return !selected.isEmpty }
        if action == #selector(openWith(_:)) { return selected.count == 1 && isDocument(selected[0]) }
        if action == #selector(resetAssociation(_:)) {
            let file = selected.count == 1 ? selected.first : nil
            menuItem.title = file.flatMap { FileAssociations.fileExtension(for: $0) }.map { "Reset Application for .\($0)" } ?? "Reset Default Application"
            return file.map { isDocument($0) && associations.application(for: $0) != nil } ?? false
        }
        if action == #selector(revealSelected(_:)) { return selected.count == 1 }
        if action == #selector(openInTab(_:)) { return selected.count == 1 && canBrowse(selected[0]) }
        guard operation == nil else { return false }
        if action == #selector(createFile(_:)) || action == #selector(createFolder(_:)) { return !isSearch && lastReadError == nil }
        if action == #selector(pasteFiles(_:)) { return !isSearch && !clipboardURLs().isEmpty }
        if action == #selector(renameSelected(_:)) { return selected.count == 1 }
        if action == #selector(extractArchive(_:)) { return selected.count == 1 && ["zip", "7z"].contains(selected[0].pathExtension.lowercased()) }
        return !selected.isEmpty
    }

    func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "Could Not Complete the Action"
        alert.informativeText = error.localizedDescription; alert.alertStyle = .warning
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
    func namePrompt(title: String, value: String, confirm: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: value); field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        field.setAccessibilityLabel("Name"); alert.accessoryView = field
        alert.addButton(withTitle: confirm); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        field.selectText(nil)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
    func chooseDirectory(title: String, initial: URL? = nil) -> URL? {
        let panel = NSOpenPanel(); panel.title = title; panel.prompt = "Choose"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.directoryURL = initial ?? current; panel.showsHiddenFiles = shownHidden
        return panel.runModal() == .OK ? panel.url : nil
    }
    func runOperation(_ title: String, work: @escaping (Cancellation, @escaping (String) -> Void) throws -> String) {
        guard operation == nil else { NSSound.beep(); return }
        let token = Cancellation(); operation = token; completionMessage = nil; updateStatus(); status.stringValue = title
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work(token) { message in DispatchQueue.main.async { self?.status.stringValue = message } } }
            DispatchQueue.main.async {
                guard let self else { return }
                self.operation = nil
                self.updateStatus()
                if !self.isSearch { self.reloadPreservingSelection() }
                else { self.startSearch(nil) }
                switch result {
                case .success(let message): self.completionMessage = message; self.updateStatus()
                case .failure(let error):
                    if error is CancellationError { self.completionMessage = "Operation cancelled"; self.updateStatus() }
                    else { self.showError(error) }
                }
            }
        }
    }
    func cancelCurrent() {
        if let operation { operation.cancel(); status.stringValue = "Cancelling… The current file may take a while." }
        else { search?.cancel() }
    }

    @objc func createFolder(_ sender: Any?) { create(directory: true) }
    @objc func createFile(_ sender: Any?) { create(directory: false) }
    func create(directory: Bool) {
        guard operation == nil, !isSearch else { NSSound.beep(); return }
        guard let name = namePrompt(title: directory ? "New Folder" : "New Empty File", value: directory ? "New Folder" : "", confirm: "Create") else { return }
        let parent = current
        runOperation("Creating…") { [weak self] token, _ in
            try token.check()
            let url = try Files.create(name: name, in: parent, directory: directory)
            DispatchQueue.main.async { if self?.current == parent { self?.revealURL = url } }
            return "Created: \(name)"
        }
    }
    func canBrowse(_ url: URL) -> Bool { (try? FileEntry(url: url.resolvingSymlinksInPath()).canBrowse) == true }
    @objc func openSelected(_ sender: Any?) {
        if parentSelected { up(); return }
        let urls = selected
        if urls.count == 1 && canBrowse(urls[0]) { navigate(urls[0]); return }
        for url in urls {
            if canBrowse(url) { tabs.append(BrowserTab(url)); rebuildTabs() }
            else { openFile(url) }
        }
    }
    @objc func openInTab(_ sender: Any?) {
        guard let url = selected.first, canBrowse(url) else { return }
        captureTab(); tabs.append(BrowserTab(url)); selectTab(tabs.count - 1)
    }
    @objc func revealSelected(_ sender: Any?) {
        guard let url = selected.first else { return }; navigate(url.deletingLastPathComponent(), reveal: url)
    }
    @objc func renameSelected(_ sender: Any?) {
        guard operation == nil, selected.count == 1, let url = selected.first else { return }
        guard let name = namePrompt(title: "Rename", value: url.lastPathComponent, confirm: "Rename") else { return }
        runOperation("Renaming…") { [weak self] token, _ in
            try token.check(); let target = try Files.rename(url, to: name)
            DispatchQueue.main.async { if self?.current == target.deletingLastPathComponent() { self?.revealURL = target } }
            return "Renamed: \(name)"
        }
    }
    func copyCurrentPath() { Self.clipboard.clearContents(); Self.clipboard.setString(current.path, forType: .string) }
    @objc func copyPaths(_ sender: Any?) {
        let urls = selected.isEmpty ? [current] : selected
        Self.clipboard.clearContents(); Self.clipboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }
    @objc func copyFiles(_ sender: Any?) {
        if let editor = window?.firstResponder as? NSTextView { editor.copy(sender); return }
        guard !selected.isEmpty else { return }
        Self.clipboard.clearContents(); Self.clipboard.writeObjects(selected.map { $0 as NSURL }); Self.cutURLs = []; table.reloadData()
    }
    @objc func cutFiles(_ sender: Any?) {
        if let editor = window?.firstResponder as? NSTextView { editor.cut(sender); return }
        guard operation == nil, !selected.isEmpty else { return }
        let urls = selected
        Self.clipboard.clearContents(); Self.clipboard.writeObjects(urls.map { $0 as NSURL })
        Self.cutURLs = urls; Self.cutChange = Self.clipboard.changeCount; table.reloadData()
    }
    func clipboardURLs() -> [URL] {
        Self.clipboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    @objc func pasteFiles(_ sender: Any?) {
        if let editor = window?.firstResponder as? NSTextView { editor.paste(sender); return }
        guard !isSearch else { return }
        let urls = clipboardURLs(); guard !urls.isEmpty else { return }
        let move = Self.cutChange == Self.clipboard.changeCount && urls == Self.cutURLs
        transfer(urls, to: current, move: move)
    }
    @objc func selectAllFiles(_ sender: Any?) {
        if let editor = window?.firstResponder as? NSTextView { editor.selectAll(sender) }
        else { table.selectRowIndexes(IndexSet(integersIn: row(forEntry: 0)..<numberOfRows(in: table)), byExtendingSelection: false) }
    }
    @objc func copyTo(_ sender: Any?) {
        let urls = selected; guard operation == nil, !urls.isEmpty, let directory = chooseDirectory(title: "Copy to Folder", initial: otherPane?.current) else { return }
        transfer(urls, to: directory, move: false)
    }
    @objc func moveTo(_ sender: Any?) {
        let urls = selected; guard operation == nil, !urls.isEmpty, let directory = chooseDirectory(title: "Move to Folder", initial: otherPane?.current) else { return }
        transfer(urls, to: directory, move: true)
    }
    func resolveConflict(_ target: URL) -> ConflictChoice {
        let alert = NSAlert(); alert.messageText = "“\(target.lastPathComponent)” already exists"
        alert.informativeText = "\(target.deletingLastPathComponent().path)\nReplacing overwrites the entire existing item. Folders are not merged."
        ["Keep Both", "Skip", "Replace", "Cancel Operation"].forEach { alert.addButton(withTitle: $0) }
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .skip
        case .alertThirdButtonReturn: return .replace
        default: return .cancel
        }
    }
    func transfer(_ urls: [URL], to directory: URL, move: Bool) {
        guard operation == nil else { NSSound.beep(); return }
        let sources = Files.topLevelSelection(urls)
        runOperation(move ? "Moving…" : "Copying…") { [weak self] token, report in
            var completed = 0; var skipped = 0; var errors: [String] = []
            var moved: [URL] = []
            for (index, source) in sources.enumerated() {
                if token.isCancelled { break }
                report("\(move ? "Moving" : "Copying") \(index + 1)/\(sources.count): \(source.lastPathComponent)")
                do {
                    let result = try Files.transfer(source, to: directory, move: move, cancellation: token) { target in
                        DispatchQueue.main.sync { self?.resolveConflict(target) ?? .cancel }
                    }
                    if result != nil { completed += 1; if move { moved.append(source) } }
                    else { skipped += 1 }
                } catch is CancellationError { break }
                catch { errors.append("\(source.lastPathComponent): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async {
                Self.cutURLs.removeAll { item in moved.contains { item.path == $0.path || item.path.hasPrefix($0.path + "/") } }
                if Self.cutChange == Self.clipboard.changeCount && !moved.isEmpty {
                    Self.clipboard.clearContents()
                    Self.clipboard.writeObjects(Self.cutURLs.map { $0 as NSURL })
                    Self.cutChange = Self.clipboard.changeCount
                }
            }
            let summary = "Completed: \(completed) of \(sources.count) · Skipped: \(skipped)" + (token.isCancelled ? " · Cancelled; remaining items were not processed" : "")
            if !errors.isEmpty { throw FileProblem.message(summary + "\n\n" + errors.joined(separator: "\n")) }
            return summary
        }
    }
    @objc func trashSelected(_ sender: Any?) {
        guard operation == nil else { return }
        let urls = Files.topLevelSelection(selected); guard !urls.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "Move \(urls.count) item(s) to Trash?"
        alert.informativeText = urls.prefix(5).map(\.lastPathComponent).joined(separator: "\n")
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runOperation("Moving to Trash…") { token, report in
            var completed = 0; var errors: [String] = []
            for url in urls {
                if token.isCancelled { break }
                report("Move to Trash: \(url.lastPathComponent)")
                do { try Files.trash(url); completed += 1 }
                catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            let summary = "Trashed: \(completed) of \(urls.count)" + (token.isCancelled ? " · Cancelled" : "")
            if !errors.isEmpty { throw FileProblem.message(summary + "\n" + errors.joined(separator: "\n")) }
            return summary
        }
    }
    @objc func createZIP(_ sender: Any?) { createArchive(format: "zip") }
    @objc func create7z(_ sender: Any?) { createArchive(format: "7z") }
    func createArchive(format: String) {
        guard operation == nil, !selected.isEmpty else { return }
        let sources = selected
        let panel = NSSavePanel(); panel.title = "Create \(format.uppercased())"; panel.prompt = "Create"
        panel.directoryURL = current; panel.showsHiddenFiles = shownHidden
        panel.nameFieldStringValue = (sources.count == 1 ? sources[0].lastPathComponent : "Archive") + "." + format
        guard panel.runModal() == .OK, var destination = panel.url else { return }
        if destination.pathExtension.lowercased() != format { destination.appendPathExtension(format) }
        runOperation("Creating archive…") { token, _ in
            try Archives.create(sources, at: destination, format: format, cancellation: token)
            return "Archive created: \(destination.lastPathComponent)"
        }
    }
    @objc func extractArchive(_ sender: Any?) {
        guard operation == nil, selected.count == 1, let archive = selected.first,
              let parent = chooseDirectory(title: "Extract Archive To") else { return }
        let suggestion = Files.availableName(for: parent.appendingPathComponent(archive.deletingPathExtension().lastPathComponent))
        guard let name = namePrompt(title: "Extraction Folder", value: suggestion.lastPathComponent, confirm: "Extract") else { return }
        do {
            let destination = try Files.named(name, in: parent)
            runOperation("Extracting…") { token, _ in
                try Archives.extract(archive, to: destination, cancellation: token)
                return "Extracted: \(destination.lastPathComponent)"
            }
        } catch { showError(error) }
    }
    func eject(_ url: URL) {
        guard operation == nil else { showError(FileProblem.message("Wait for the file operation to finish before ejecting the disk.")); return }
        if current.path == url.path || current.path.hasPrefix(url.path + "/") { watcher?.cancel(); watcher = nil }
        runOperation("Ejecting disk…") { _, _ in
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            return "The disk can now be disconnected"
        }
    }
}
