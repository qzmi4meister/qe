import AppKit
import QECore
import Darwin

struct BrowserTab {
    let id = UUID()
    var history: [URL]
    var position = 0
    var selection: Set<String> = []
    var scroll: CGFloat = 0
    var url: URL { history[position] }
    init(_ url: URL) { history = [url] }
}

final class BrowserController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate, NSMenuItemValidation, NSWindowDelegate {
    let preferences: UserDefaults
    var tabs: [BrowserTab] = []
    var active = 0
    var entries: [FileEntry] = []
    var hasParentRow = false
    let table = FileTable()
    let scroll = NSScrollView()
    let pathField = NSTextField()
    let searchField = NSSearchField()
    let sidebar = NSStackView()
    let tabsStack = NSStackView()
    let status = NSTextField(labelWithString: "")
    let emptyLabel = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()
    var cancelButton: ActionButton!
    var backButton: ActionButton!
    var forwardButton: ActionButton!
    var hiddenButton: NSButton!
    var operation: Cancellation?
    var search: Cancellation?
    var generation = UUID()
    var isSearch = false
    var isLoading = false
    var lastReadError: String?
    var completionMessage: String?
    var watcher: DispatchSourceFileSystemObject?
    var refreshWork: DispatchWorkItem?
    var cutURLs: [URL] = []
    var cutChange = -1
    var revealURL: URL?
    var sortKey = "name"
    var ascending = true
    var shownHidden: Bool { preferences.object(forKey: "showHidden") as? Bool ?? true }
    var current: URL { tabs[active].url }
    var selected: [URL] { table.selectedRowIndexes.compactMap { entry(at: $0)?.url } }
    var parentSelected: Bool { hasParentRow && table.selectedRowIndexes == IndexSet(integer: 0) }
    func isParentRow(_ row: Int) -> Bool { hasParentRow && row == 0 }
    func row(forEntry index: Int) -> Int { index + (hasParentRow ? 1 : 0) }
    func entry(at row: Int) -> FileEntry? {
        let index = row - (hasParentRow ? 1 : 0)
        return entries.indices.contains(index) ? entries[index] : nil
    }
    func rows(matching paths: Set<String>) -> IndexSet {
        IndexSet(entries.indices.filter { paths.contains(entries[$0].url.path) }.map { row(forEntry: $0) })
    }
    let dateFormatter: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "ru_RU"); value.dateStyle = .short; value.timeStyle = .short; return value
    }()

    init(startURL: URL? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let saved = preferences.stringArray(forKey: "tabs") ?? []
        tabs = (startURL.map { [$0] } ?? saved.map { URL(fileURLWithPath: $0) }).map(BrowserTab.init)
        if tabs.isEmpty { tabs = [BrowserTab(FileManager.default.homeDirectoryForCurrentUser)] }
        active = min(max(0, preferences.integer(forKey: "activeTab")), tabs.count - 1)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "QE"
        window.minSize = NSSize(width: 780, height: 450)
        window.tabbingMode = .disallowed
        window.center()
        window.delegate = self
        buildUI()
        window.contentMinSize = NSSize(width: 780, height: 450)
        window.setContentSize(NSSize(width: 1060, height: 680))
        if !CommandLine.arguments.contains("--ui-check") {
            window.setFrameUsingName("QEBrowser")
            window.setFrameAutosaveName("QEBrowser")
        }
        buildMenu()
        refreshSidebar()
        rebuildTabs()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumesChanged), name: name, object: nil)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func buildUI() {
        backButton = iconButton("Назад", "chevron.left") { [weak self] in self?.history(-1) }
        forwardButton = iconButton("Вперёд", "chevron.right") { [weak self] in self?.history(1) }
        let up = iconButton("На уровень вверх", "arrow.up") { [weak self] in self?.up() }
        pathField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pathField.lineBreakMode = .byTruncatingHead
        pathField.setAccessibilityLabel("Полный путь")
        pathField.target = self; pathField.action = #selector(enterPath)
        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let pathCopy = iconButton("Копировать текущий путь", "doc.on.doc") { [weak self] in self?.copyCurrentPath() }
        let navigation = inset(horizontal([backButton, forwardButton, up, pathField, pathCopy]))

        tabsStack.orientation = .horizontal; tabsStack.spacing = 4; tabsStack.alignment = .centerY
        let tabScroll = NSScrollView(); tabScroll.hasHorizontalScroller = true; tabScroll.autohidesScrollers = true; tabScroll.drawsBackground = false
        let tabDocument = NSView(); tabDocument.translatesAutoresizingMaskIntoConstraints = false
        tabsStack.translatesAutoresizingMaskIntoConstraints = false; tabDocument.addSubview(tabsStack)
        tabScroll.documentView = tabDocument
        NSLayoutConstraint.activate([
            tabsStack.leadingAnchor.constraint(equalTo: tabDocument.leadingAnchor), tabsStack.trailingAnchor.constraint(equalTo: tabDocument.trailingAnchor),
            tabsStack.topAnchor.constraint(equalTo: tabDocument.topAnchor), tabsStack.bottomAnchor.constraint(equalTo: tabDocument.bottomAnchor),
            tabDocument.heightAnchor.constraint(equalTo: tabScroll.contentView.heightAnchor)
        ])
        tabScroll.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let addTab = iconButton("Новая вкладка", "plus") { [weak self] in self?.newTab(nil) }
        let tabRow = inset(horizontal([tabScroll, addTab]), y: 2)

        let folder = ActionButton("Новая папка", symbol: "folder.badge.plus") { [weak self] in self?.createFolder(nil) }
        let file = ActionButton("Новый файл", symbol: "doc.badge.plus") { [weak self] in self?.createFile(nil) }
        hiddenButton = NSButton(checkboxWithTitle: "Скрытые", target: self, action: #selector(toggleHidden))
        hiddenButton.state = shownHidden ? .on : .off
        hiddenButton.toolTip = "Показывать скрытые файлы. Настройка сохраняется."
        searchField.placeholderString = "Поиск по именам…"
        searchField.setAccessibilityLabel("Поиск по именам во вложенных папках")
        searchField.sendsSearchStringImmediately = false; searchField.sendsWholeSearchString = true
        searchField.target = self; searchField.action = #selector(startSearch)
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = inset(horizontal([folder, file, hiddenButton, spacer, searchField]))

        sidebar.orientation = .vertical; sidebar.alignment = .leading; sidebar.spacing = 5
        let sidebarBody = inset(sidebar, x: 10, y: 14)
        let sidebarScroll = NSScrollView(); sidebarScroll.drawsBackground = false; sidebarScroll.hasVerticalScroller = true; sidebarScroll.autohidesScrollers = true
        sidebarScroll.documentView = sidebarBody
        sidebarBody.translatesAutoresizingMaskIntoConstraints = false
        sidebarBody.widthAnchor.constraint(equalTo: sidebarScroll.contentView.widthAnchor).isActive = true
        sidebarScroll.widthAnchor.constraint(equalToConstant: 178).isActive = true

        table.delegate = self; table.dataSource = self
        table.rowHeight = 30; table.intercellSpacing = NSSize(width: 12, height: 0)
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true; table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.style = .plain
        table.target = self; table.doubleAction = #selector(openSelected)
        table.openSelection = { [weak self] in self?.openSelected(nil) }
        table.renameSelection = { [weak self] in self?.renameSelected(nil) }
        table.goUp = { [weak self] in self?.up() }
        table.setAccessibilityLabel("Файлы")
        for (key, title, width) in [("name", "Имя", 390.0), ("size", "Размер", 95.0), ("date", "Изменён", 145.0), ("parent", "Папка", 250.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key)); column.title = title
            column.width = width; column.minWidth = key == "name" ? 180 : 70
            if key != "parent" { column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true) }
            column.isHidden = key == "parent"
            table.addTableColumn(column)
        }
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        table.registerForDraggedTypes([.fileURL]); table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        emptyLabel.textColor = .secondaryLabelColor; emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byWordWrapping; emptyLabel.maximumNumberOfLines = 4
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        let listContainer = NSView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(scroll); listContainer.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: listContainer.topAnchor), scroll.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: listContainer.centerXAnchor), emptyLabel.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: listContainer.widthAnchor, constant: -48)
        ])
        let verticalLine = divider(); verticalLine.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let body = NSView()
        body.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        for view in [sidebarScroll, verticalLine, listContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(view)
            view.topAnchor.constraint(equalTo: body.topAnchor).isActive = true
            view.bottomAnchor.constraint(equalTo: body.bottomAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            sidebarScroll.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            verticalLine.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor),
            listContainer.leadingAnchor.constraint(equalTo: verticalLine.trailingAnchor),
            listContainer.trailingAnchor.constraint(equalTo: body.trailingAnchor)
        ])

        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingMiddle
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        cancelButton = ActionButton("Отменить") { [weak self] in self?.cancelCurrent() }; cancelButton.controlSize = .small; cancelButton.isHidden = true
        let footer = inset(horizontal([status, progress, cancelButton]), y: 5)
        let root = WindowBackground(); root.translatesAutoresizingMaskIntoConstraints = false
        let topLine = divider(), bottomLine = divider()
        let rows = [navigation, tabRow, actions, topLine, body, bottomLine, footer]
        for (index, view) in rows.enumerated() {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor).isActive = true
            view.topAnchor.constraint(equalTo: index == 0 ? root.topAnchor : rows[index - 1].bottomAnchor).isActive = true
        }
        navigation.heightAnchor.constraint(equalToConstant: 44).isActive = true
        tabRow.heightAnchor.constraint(equalToConstant: 38).isActive = true
        actions.heightAnchor.constraint(equalToConstant: 44).isActive = true
        topLine.heightAnchor.constraint(equalToConstant: 1).isActive = true
        bottomLine.heightAnchor.constraint(equalToConstant: 1).isActive = true
        footer.heightAnchor.constraint(equalToConstant: 30).isActive = true
        footer.bottomAnchor.constraint(equalTo: root.bottomAnchor).isActive = true
        let content = window!.contentView!; content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    func iconButton(_ label: String, _ symbol: String, action: @escaping () -> Void) -> ActionButton {
        let button = ActionButton(label, symbol: symbol, action: action)
        button.imagePosition = .imageOnly; button.toolTip = label
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    func refreshSidebar() {
        sidebar.arrangedSubviews.forEach { sidebar.removeArrangedSubview($0); $0.removeFromSuperview() }
        func heading(_ title: String) {
            let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = .secondaryLabelColor
            sidebar.addArrangedSubview(inset(label, x: 4, y: 7))
        }
        func place(_ title: String, _ symbol: String, _ url: URL, ejectable: Bool = false) {
            let button = ActionButton(title, symbol: symbol) { [weak self] in self?.navigate(url) }
            button.bezelStyle = .recessed; button.alignment = .left; button.lineBreakMode = .byTruncatingMiddle
            button.state = current.standardizedFileURL.path == url.standardizedFileURL.path ? .on : .off
            button.toolTip = url.path
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            var views: [NSView] = [button]
            if ejectable { views.append(iconButton("Извлечь \(title)", "eject") { [weak self] in self?.eject(url) }) }
            let row = horizontal(views, spacing: 2); sidebar.addArrangedSubview(row)
            button.widthAnchor.constraint(equalTo: sidebar.widthAnchor, constant: -32).isActive = true
            row.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        }
        heading("Папки")
        place("Домашняя", "house", FileManager.default.homeDirectoryForCurrentUser)
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { place("Загрузки", "arrow.down.circle", downloads) }
        heading("Диски")
        place("Macintosh HD", "internaldrive", URL(fileURLWithPath: "/"))
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey, .volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey], options: [.skipHiddenVolumes]) ?? []
        for url in volumes where url.path != "/" {
            let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey, .volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey])
            if values?.volumeIsInternal == true { continue }
            place(values?.volumeLocalizedName ?? url.lastPathComponent, "externaldrive", url,
                ejectable: values?.volumeIsEjectable == true || values?.volumeIsRemovable == true)
        }
    }

    func saveTabs() {
        preferences.set(tabs.map { $0.url.path }, forKey: "tabs")
        preferences.set(active, forKey: "activeTab")
    }
    func captureTab() {
        if !isSearch {
            tabs[active].selection = Set(selected.map(\.path))
            tabs[active].scroll = max(0, scroll.contentView.bounds.origin.y + (table.headerView?.frame.height ?? 0))
        }
    }
    func rebuildTabs() {
        tabsStack.arrangedSubviews.forEach { tabsStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, tab) in tabs.enumerated() {
            let button = TabButton(title: tab.url.lastPathComponent.isEmpty ? "/" : tab.url.lastPathComponent) { [weak self] in self?.closeTab(at: index) }
            button.state = index == active ? .on : .off; button.toolTip = tab.url.path
            button.widthAnchor.constraint(equalToConstant: 175).isActive = true
            button.selectTab = { [weak self] in self?.selectTab(index) }
            button.receiveFiles = { [weak self] urls, move in self?.transfer(urls, to: tab.url, move: move) }
            tabsStack.addArrangedSubview(button)
        }
        saveTabs()
    }
    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        captureTab(); active = index; leaveSearch(); rebuildTabs(); refreshSidebar(); reload()
    }
    @objc func newTab(_ sender: Any?) {
        captureTab(); tabs.append(BrowserTab(current)); active = tabs.count - 1; leaveSearch(); rebuildTabs(); reload()
    }
    @objc func closeCurrentTab(_ sender: Any?) { closeTab(at: active) }
    func closeTab(at index: Int) {
        if tabs.count == 1 { window?.performClose(nil); return }
        captureTab(); tabs.remove(at: index)
        if index < active { active -= 1 } else if active >= tabs.count { active = tabs.count - 1 }
        leaveSearch(); rebuildTabs(); refreshSidebar(); reload()
    }
    func navigate(_ url: URL, reveal: URL? = nil) {
        captureTab(); leaveSearch(); completionMessage = nil
        let normalized = url.standardizedFileURL
        if normalized.path != current.path {
            tabs[active].history = Array(tabs[active].history.prefix(tabs[active].position + 1)) + [normalized]
            tabs[active].position += 1; tabs[active].selection = []; tabs[active].scroll = 0
        }
        revealURL = reveal; rebuildTabs(); refreshSidebar(); reload()
    }
    func history(_ delta: Int) {
        let newPosition = tabs[active].position + delta
        guard tabs[active].history.indices.contains(newPosition) else { return }
        captureTab(); tabs[active].position = newPosition; tabs[active].selection = []; tabs[active].scroll = 0
        leaveSearch(); rebuildTabs(); refreshSidebar(); reload()
    }
    func up() { navigate(current.deletingLastPathComponent()) }
    @objc func enterPath(_ sender: Any?) {
        let path = (pathField.stringValue as NSString).expandingTildeInPath
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : current.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            showError(FileProblem.message("Папка не найдена или недоступна: \(path)")); return
        }
        navigate(url); window?.makeFirstResponder(table)
    }
    @objc func focusPath(_ sender: Any?) { window?.makeFirstResponder(pathField); pathField.selectText(nil) }
    @objc func focusSearch(_ sender: Any?) { window?.makeFirstResponder(searchField) }
    @objc func toggleHidden(_ sender: Any?) {
        preferences.set(!shownHidden, forKey: "showHidden"); hiddenButton.state = shownHidden ? .on : .off
        if isSearch { startSearch(nil) } else { reloadPreservingSelection() }
    }
    @objc func becameActive() { refreshSidebar(); if !isSearch { reloadPreservingSelection() } }
    @objc func volumesChanged() { refreshSidebar(); if !isSearch { reloadPreservingSelection() } }
    @objc func refresh(_ sender: Any?) { if isSearch { startSearch(nil) } else { reloadPreservingSelection() } }
    func reloadPreservingSelection() { captureTab(); reload() }

    func sorted(_ values: [FileEntry]) -> [FileEntry] {
        Files.sorted(values, key: sortKey, ascending: ascending)
    }
    func reload() {
        guard !isSearch else { return }
        generation = UUID(); let request = generation; let directory = current; let hidden = shownHidden
        let key = sortKey; let direction = ascending
        isLoading = true; lastReadError = nil
        pathField.stringValue = directory.path
        backButton.isEnabled = tabs[active].position > 0
        forwardButton.isEnabled = tabs[active].position < tabs[active].history.count - 1
        watch(directory)
        updateStatus()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { Files.sorted(try Files.list(directory, hidden: hidden), key: key, ascending: direction) }
            DispatchQueue.main.async {
                guard let self, self.generation == request else { return }
                self.isLoading = false
                switch result {
                case .success(let files): self.entries = files
                case .failure(let error): self.entries = []; self.lastReadError = error.localizedDescription
                }
                self.hasParentRow = directory.path != "/"
                self.table.reloadData()
                let urls = self.revealURL.map { Set([$0.path]) } ?? self.tabs[self.active].selection
                self.table.selectRowIndexes(self.rows(matching: urls), byExtendingSelection: false)
                if self.revealURL != nil, let index = self.table.selectedRowIndexes.first { self.table.scrollRowToVisible(index) }
                else {
                    self.scroll.contentView.scroll(to: NSPoint(x: 0, y: self.tabs[self.active].scroll - (self.table.headerView?.frame.height ?? 0)))
                    self.scroll.reflectScrolledClipView(self.scroll.contentView)
                }
                self.revealURL = nil; self.updateStatus()
            }
        }
    }
    func watch(_ directory: URL) {
        watcher?.cancel(); watcher = nil; refreshWork?.cancel()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .attrib, .revoke], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, !self.isSearch else { return }
            self.refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reloadPreservingSelection() }
            self.refreshWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        source.setCancelHandler { Darwin.close(fd) }; source.resume(); watcher = source
    }
    func leaveSearch() {
        search?.cancel(); search = nil; isSearch = false; searchField.stringValue = ""
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("parent"))?.isHidden = true
    }
    @objc func startSearch(_ sender: Any?) {
        let query = searchField.stringValue
        guard !query.isEmpty else { leaveSearch(); reload(); return }
        if !isSearch { captureTab() }
        search?.cancel(); watcher?.cancel(); watcher = nil; refreshWork?.cancel()
        generation = UUID(); let request = generation; let directory = current; let hidden = shownHidden
        let token = Cancellation(); search = token; isSearch = true; isLoading = false; lastReadError = nil
        entries = []; hasParentRow = false; table.reloadData(); table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("parent"))?.isHidden = false
        updateStatus()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Files.search(in: directory, query: query, hidden: hidden, cancellation: token) { batch in
                DispatchQueue.main.async {
                    guard let self, self.generation == request else { return }
                    let selection = Set(self.selected.map(\.path))
                    self.entries = self.sorted(self.entries + batch); self.table.reloadData()
                    self.table.selectRowIndexes(self.rows(matching: selection), byExtendingSelection: false)
                    self.updateStatus()
                }
            } }
            DispatchQueue.main.async {
                guard let self, self.generation == request else { return }
                self.search = nil; self.updateStatus()
                switch result {
                case .success(let unreadable): if unreadable > 0 { self.status.stringValue += " · Недоступно папок: \(unreadable)" }
                case .failure(let error):
                    if error is CancellationError { self.status.stringValue += " · Поиск остановлен" }
                    else { self.showError(error) }
                }
            }
        }
    }
    func updateStatus() {
        emptyLabel.isHidden = !entries.isEmpty
        emptyLabel.stringValue = lastReadError.map { "Папка недоступна\n\($0)" } ??
            (isLoading ? "Чтение папки…" : (isSearch ? (search != nil ? "Идёт поиск…" : "Ничего не найдено") : "Папка пуста\nСоздайте папку или файл кнопками сверху"))
        if operation == nil {
            status.stringValue = "\(isSearch ? "Найдено" : "Элементов"): \(entries.count)" +
                (selected.isEmpty ? "" : " · Выбрано: \(selected.count)") + (completionMessage.map { " · " + $0 } ?? "")
        }
        let working = operation != nil || search != nil
        cancelButton.isHidden = !working
        if working { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { row(forEntry: entries.count) }
    func tableViewSelectionDidChange(_ notification: Notification) { updateStatus() }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first else { return }
        sortKey = descriptor.key ?? "name"; ascending = descriptor.ascending
        if isLoading { reload(); return }
        let selection = Set(selected.map(\.path)); entries = sorted(entries); table.reloadData()
        table.selectRowIndexes(rows(matching: selection), byExtendingSelection: false)
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView) ?? makeCell(column.identifier)
        let label = cell.textField!
        if isParentRow(row) {
            label.stringValue = column.identifier.rawValue == "name" ? ".." : ""
            label.textColor = .labelColor
            cell.imageView?.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "На уровень выше")
            cell.imageView?.contentTintColor = .systemBlue
            cell.toolTip = "На уровень выше: \(current.deletingLastPathComponent().path)"
            cell.alphaValue = 1
            return cell
        }
        guard let entry = entry(at: row) else { return nil }
        switch column.identifier.rawValue {
        case "name":
            label.stringValue = entry.name
            cell.imageView?.image = NSImage(systemSymbolName: entry.isLink ? "link" : (entry.canBrowse ? "folder" : "doc"), accessibilityDescription: entry.canBrowse ? "Папка" : "Файл")
            cell.imageView?.contentTintColor = entry.canBrowse ? .systemBlue : .secondaryLabelColor
        case "size": label.stringValue = entry.isDirectory ? "—" : ByteCountFormatStyle(spellsOutZero: false, locale: Locale(identifier: "ru_RU")).format(entry.size)
        case "date": label.stringValue = dateFormatter.string(from: entry.modified)
        default: label.stringValue = entry.url.deletingLastPathComponent().path
        }
        label.textColor = entry.isHidden ? .secondaryLabelColor : .labelColor
        cell.toolTip = entry.url.path
        cell.alphaValue = cutChange == NSPasteboard.general.changeCount && cutURLs.contains(entry.url) ? 0.5 : 1
        return cell
    }
    func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView(); cell.identifier = identifier
        let label = NSTextField(labelWithString: ""); label.font = .systemFont(ofSize: 13); label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(label); cell.textField = label
        var leading = cell.leadingAnchor
        if identifier.rawValue == "name" {
            let icon = NSImageView(); icon.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(icon); cell.imageView = icon
            NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18)])
            leading = icon.trailingAnchor
        }
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leading, constant: 7), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { entry(at: row)?.url as NSURL? }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard operation == nil, !isParentRow(row) else { return [] }
        if entry(at: row)?.canBrowse == true { tableView.setDropRow(row, dropOperation: .on) }
        else { if isSearch { return [] }; tableView.setDropRow(-1, dropOperation: .on) }
        return NSEvent.modifierFlags.contains(.command) ? .move : .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty, !isParentRow(row) else { return false }
        let destination = entry(at: row).flatMap { $0.canBrowse ? $0.url : nil } ?? current
        transfer(urls, to: destination, move: NSEvent.modifierFlags.contains(.command)); return true
    }
    func windowWillClose(_ notification: Notification) { captureTab(); saveTabs(); watcher?.cancel(); search?.cancel() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if operation != nil { showError(FileProblem.message("Дождитесь завершения операции или отмените её перед закрытием.")); return false }
        return true
    }
}
