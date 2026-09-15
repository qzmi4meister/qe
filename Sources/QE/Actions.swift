import AppKit
import QECore

extension BrowserController {
    func buildMenu() {
        func item(_ title: String, _ action: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; item.keyEquivalentModifierMask = modifiers; return item
        }
        let bar = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) {
            let root = NSMenuItem(); root.title = title; let menu = NSMenu(title: title)
            items.forEach(menu.addItem); root.submenu = menu; bar.addItem(root)
        }
        let quit = NSMenuItem(title: "Завершить QE", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let about = NSMenuItem(title: "О QE", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let hide = NSMenuItem(title: "Скрыть QE", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu("QE", [about, .separator(), hide, .separator(), quit])
        menu("Файл", [item("Новая папка", #selector(createFolder(_:)), "n", modifiers: [.command, .shift]),
            item("Новый файл", #selector(createFile(_:)), "n"), .separator(),
            item("Новая вкладка", #selector(newTab(_:)), "t"), item("Закрыть вкладку", #selector(closeCurrentTab(_:)), "w"), .separator(),
            item("Открыть", #selector(openSelected(_:)), "o"), item("Открыть с помощью…", #selector(openWith(_:))),
            item("Сбросить приложение для расширения", #selector(resetAssociation(_:))), item("Переименовать…", #selector(renameSelected(_:))),
            item("В корзину", #selector(trashSelected(_:)), "\u{8}"), .separator(),
            item("Создать ZIP…", #selector(createZIP(_:))), item("Создать 7z…", #selector(create7z(_:))), item("Распаковать…", #selector(extractArchive(_:)))])
        menu("Правка", [item("Вырезать", #selector(cutFiles(_:)), "x"), item("Копировать", #selector(copyFiles(_:)), "c"),
            item("Вставить", #selector(pasteFiles(_:)), "v"), item("Выбрать всё", #selector(selectAllFiles(_:)), "a"), .separator(),
            item("Копировать путь", #selector(copyPaths(_:)), "c", modifiers: [.command, .option]),
            item("Копировать в…", #selector(copyTo(_:))), item("Переместить в…", #selector(moveTo(_:)))])
        menu("Вид", [item("Показать скрытые файлы", #selector(toggleHidden(_:)), ".", modifiers: [.command, .shift]),
            item("Обновить", #selector(refresh(_:)), "r"), item("Перейти к пути", #selector(focusPath(_:)), "l"),
            item("Поиск по именам", #selector(focusSearch(_:)), "f"), item("Перейти к файлу", #selector(revealSelected(_:)))])
        let windowMenu = NSMenu(title: "Окно")
        windowMenu.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Развернуть", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(); windowItem.submenu = windowMenu; bar.addItem(windowItem)
        NSApp.windowsMenu = windowMenu; NSApp.mainMenu = bar

        let context = NSMenu()
        [item("Открыть", #selector(openSelected(_:))), item("Открыть с помощью…", #selector(openWith(_:))),
         item("Сбросить приложение для расширения", #selector(resetAssociation(_:))), item("Открыть в новой вкладке", #selector(openInTab(_:))),
         item("Перейти к файлу", #selector(revealSelected(_:))), .separator(),
         item("Новая папка…", #selector(createFolder(_:))), item("Новый файл…", #selector(createFile(_:))), .separator(),
         item("Копировать", #selector(copyFiles(_:))), item("Вырезать", #selector(cutFiles(_:))), item("Вставить", #selector(pasteFiles(_:))),
         item("Копировать путь", #selector(copyPaths(_:))), .separator(),
         item("Копировать в…", #selector(copyTo(_:))), item("Переместить в…", #selector(moveTo(_:))), item("Переименовать…", #selector(renameSelected(_:))),
         .separator(), item("Создать ZIP…", #selector(createZIP(_:))), item("Создать 7z…", #selector(create7z(_:))),
         item("Распаковать…", #selector(extractArchive(_:))), .separator(), item("В корзину", #selector(trashSelected(_:)))].forEach(context.addItem)
        table.menu = context
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action
        if action == #selector(toggleHidden(_:)) { menuItem.state = shownHidden ? .on : .off; return true }
        if [#selector(focusPath(_:)), #selector(focusSearch(_:)), #selector(refresh(_:)), #selector(newTab(_:)), #selector(closeCurrentTab(_:))].contains(action) { return true }
        if action == #selector(copyPaths(_:)) { return true }
        if window?.firstResponder is NSTextView,
           [#selector(cutFiles(_:)), #selector(copyFiles(_:)), #selector(pasteFiles(_:)), #selector(selectAllFiles(_:))].contains(action) { return true }
        if action == #selector(selectAllFiles(_:)) { return !entries.isEmpty }
        if action == #selector(copyFiles(_:)) || action == #selector(openSelected(_:)) { return !selected.isEmpty }
        if action == #selector(openWith(_:)) { return selected.count == 1 && isDocument(selected[0]) }
        if action == #selector(resetAssociation(_:)) {
            let file = selected.count == 1 ? selected.first : nil
            menuItem.title = file.flatMap { FileAssociations.fileExtension(for: $0) }.map { "Сбросить приложение для .\($0)" } ?? "Сбросить приложение для расширения"
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
        let alert = NSAlert(); alert.messageText = "Не удалось завершить действие"
        alert.informativeText = error.localizedDescription; alert.alertStyle = .warning
        alert.addButton(withTitle: "Понятно"); alert.runModal()
    }
    func namePrompt(title: String, value: String, confirm: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: value); field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        field.setAccessibilityLabel("Имя"); alert.accessoryView = field
        alert.addButton(withTitle: confirm); alert.addButton(withTitle: "Отмена")
        alert.window.initialFirstResponder = field
        field.selectText(nil)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
    func chooseDirectory(title: String) -> URL? {
        let panel = NSOpenPanel(); panel.title = title; panel.prompt = "Выбрать"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.directoryURL = current; panel.showsHiddenFiles = shownHidden
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
                    if error is CancellationError { self.completionMessage = "Операция отменена"; self.updateStatus() }
                    else { self.showError(error) }
                }
            }
        }
    }
    func cancelCurrent() {
        if let operation { operation.cancel(); status.stringValue = "Отмена… Текущий файл может потребовать времени." }
        else { search?.cancel() }
    }

    @objc func createFolder(_ sender: Any?) { create(directory: true) }
    @objc func createFile(_ sender: Any?) { create(directory: false) }
    func create(directory: Bool) {
        guard operation == nil, !isSearch else { NSSound.beep(); return }
        guard let name = namePrompt(title: directory ? "Новая папка" : "Новый пустой файл", value: directory ? "Новая папка" : "", confirm: "Создать") else { return }
        let parent = current
        runOperation("Создание…") { [weak self] token, _ in
            try token.check()
            let url = try Files.create(name: name, in: parent, directory: directory)
            DispatchQueue.main.async { if self?.current == parent { self?.revealURL = url } }
            return "Создано: \(name)"
        }
    }
    func canBrowse(_ url: URL) -> Bool { (try? FileEntry(url: url.resolvingSymlinksInPath()).canBrowse) == true }
    @objc func openSelected(_ sender: Any?) {
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
        guard let name = namePrompt(title: "Переименовать", value: url.lastPathComponent, confirm: "Переименовать") else { return }
        runOperation("Переименование…") { [weak self] token, _ in
            try token.check(); let target = try Files.rename(url, to: name)
            DispatchQueue.main.async { if self?.current == target.deletingLastPathComponent() { self?.revealURL = target } }
            return "Переименовано: \(name)"
        }
    }
    func copyCurrentPath() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(current.path, forType: .string) }
    @objc func copyPaths(_ sender: Any?) {
        let urls = selected.isEmpty ? [current] : selected
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }
    @objc func copyFiles(_ sender: Any?) {
        if let editor = window?.firstResponder as? NSTextView { editor.copy(sender); return }
        guard !selected.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(selected.map { $0 as NSURL }); cutURLs = []; table.reloadData()
    }
    @objc func cutFiles(_ sender: Any?) {
        if let editor = window?.firstResponder as? NSTextView { editor.cut(sender); return }
        guard operation == nil, !selected.isEmpty else { return }
        let urls = selected
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        cutURLs = urls; cutChange = NSPasteboard.general.changeCount; table.reloadData()
    }
    func clipboardURLs() -> [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    @objc func pasteFiles(_ sender: Any?) {
        if let editor = window?.firstResponder as? NSTextView { editor.paste(sender); return }
        guard !isSearch else { return }
        let urls = clipboardURLs(); guard !urls.isEmpty else { return }
        let move = cutChange == NSPasteboard.general.changeCount && urls == cutURLs
        transfer(urls, to: current, move: move)
    }
    @objc func selectAllFiles(_ sender: Any?) {
        if let editor = window?.firstResponder as? NSTextView { editor.selectAll(sender) } else { table.selectAll(sender) }
    }
    @objc func copyTo(_ sender: Any?) {
        let urls = selected; guard !urls.isEmpty, let directory = chooseDirectory(title: "Копировать в папку") else { return }
        transfer(urls, to: directory, move: false)
    }
    @objc func moveTo(_ sender: Any?) {
        let urls = selected; guard !urls.isEmpty, let directory = chooseDirectory(title: "Переместить в папку") else { return }
        transfer(urls, to: directory, move: true)
    }
    func resolveConflict(_ target: URL) -> ConflictChoice {
        let alert = NSAlert(); alert.messageText = "«\(target.lastPathComponent)» уже существует"
        alert.informativeText = "\(target.deletingLastPathComponent().path)\nПри замене существующий элемент будет заменён целиком. Папки не объединяются."
        ["Сохранить оба", "Пропустить", "Заменить", "Отменить операцию"].forEach { alert.addButton(withTitle: $0) }
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
        runOperation(move ? "Перемещение…" : "Копирование…") { [weak self] token, report in
            var completed = 0; var skipped = 0; var errors: [String] = []
            var moved: [URL] = []
            for (index, source) in sources.enumerated() {
                if token.isCancelled { break }
                report("\(move ? "Перемещение" : "Копирование") \(index + 1)/\(sources.count): \(source.lastPathComponent)")
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
                guard let self else { return }
                self.cutURLs.removeAll { item in moved.contains { item.path == $0.path || item.path.hasPrefix($0.path + "/") } }
                if self.cutChange == NSPasteboard.general.changeCount && !moved.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects(self.cutURLs.map { $0 as NSURL })
                    self.cutChange = NSPasteboard.general.changeCount
                }
            }
            let summary = "Готово: \(completed) из \(sources.count) · Пропущено: \(skipped)" + (token.isCancelled ? " · Отменено, остальные элементы не обработаны" : "")
            if !errors.isEmpty { throw FileProblem.message(summary + "\n\n" + errors.joined(separator: "\n")) }
            return summary
        }
    }
    @objc func trashSelected(_ sender: Any?) {
        guard operation == nil else { return }
        let urls = Files.topLevelSelection(selected); guard !urls.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "Отправить в корзину: \(urls.count)?"
        alert.informativeText = urls.prefix(5).map(\.lastPathComponent).joined(separator: "\n")
        alert.addButton(withTitle: "В корзину"); alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runOperation("Перемещение в корзину…") { token, report in
            var completed = 0; var errors: [String] = []
            for url in urls {
                if token.isCancelled { break }
                report("В корзину: \(url.lastPathComponent)")
                do { try Files.trash(url); completed += 1 }
                catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            let summary = "В корзине: \(completed) из \(urls.count)" + (token.isCancelled ? " · Отменено" : "")
            if !errors.isEmpty { throw FileProblem.message(summary + "\n" + errors.joined(separator: "\n")) }
            return summary
        }
    }
    @objc func createZIP(_ sender: Any?) { createArchive(format: "zip") }
    @objc func create7z(_ sender: Any?) { createArchive(format: "7z") }
    func createArchive(format: String) {
        guard operation == nil, !selected.isEmpty else { return }
        let sources = selected
        let panel = NSSavePanel(); panel.title = "Создать \(format.uppercased())"; panel.prompt = "Создать"
        panel.directoryURL = current; panel.showsHiddenFiles = shownHidden
        panel.nameFieldStringValue = (sources.count == 1 ? sources[0].lastPathComponent : "Архив") + "." + format
        guard panel.runModal() == .OK, var destination = panel.url else { return }
        if destination.pathExtension.lowercased() != format { destination.appendPathExtension(format) }
        runOperation("Создание архива…") { token, _ in
            try Archives.create(sources, at: destination, format: format, cancellation: token)
            return "Создан архив: \(destination.lastPathComponent)"
        }
    }
    @objc func extractArchive(_ sender: Any?) {
        guard operation == nil, selected.count == 1, let archive = selected.first,
              let parent = chooseDirectory(title: "Куда распаковать архив") else { return }
        let suggestion = Files.availableName(for: parent.appendingPathComponent(archive.deletingPathExtension().lastPathComponent))
        guard let name = namePrompt(title: "Папка для распаковки", value: suggestion.lastPathComponent, confirm: "Распаковать") else { return }
        do {
            let destination = try Files.named(name, in: parent)
            runOperation("Распаковка…") { token, _ in
                try Archives.extract(archive, to: destination, cancellation: token)
                return "Распаковано: \(destination.lastPathComponent)"
            }
        } catch { showError(error) }
    }
    func eject(_ url: URL) {
        guard operation == nil else { showError(FileProblem.message("Дождитесь завершения файловой операции перед извлечением диска.")); return }
        if current.path == url.path || current.path.hasPrefix(url.path + "/") { watcher?.cancel(); watcher = nil }
        runOperation("Извлечение диска…") { _, _ in
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            return "Диск можно отключить"
        }
    }
}
