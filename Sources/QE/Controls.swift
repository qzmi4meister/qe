import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class WindowBackground: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

final class ActionButton: NSButton {
    var invoke: (() -> Void)?
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        controlSize = .regular
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        invoke = action
        target = self
        self.action = #selector(performAction)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func performAction() { invoke?() }
}

final class FileTable: NSTableView {
    var openSelection: (() -> Void)?
    var renameSelection: (() -> Void)?
    var goUp: (() -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        if row < 0 { deselectAll(nil) }
        window?.makeFirstResponder(self)
        return super.menu(for: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty { renameSelection?(); return }
        if event.keyCode == 125 && event.modifierFlags.contains(.command) { openSelection?(); return }
        if event.keyCode == 126 && event.modifierFlags.contains(.command) { goUp?(); return }
        super.keyDown(with: event)
    }
}

final class TabButton: NSButton {
    let closeButton: ActionButton
    var selectTab: (() -> Void)?
    var receiveFiles: (([URL], Bool) -> Void)?
    override var state: NSControl.StateValue {
        didSet {
            closeButton.contentTintColor = state == .on ? .white : .secondaryLabelColor
            needsDisplay = true
        }
    }
    init(title: String, close: @escaping () -> Void) {
        closeButton = ActionButton("Close Tab", symbol: "xmark", action: close)
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .recessed
        setButtonType(.toggle)
        lineBreakMode = .byTruncatingMiddle
        target = self; action = #selector(selectAction)
        registerForDraggedTypes([.fileURL])
        closeButton.title = ""
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.toolTip = "Close Tab"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        if selected {
            NSColor(srgbRed: 0.13, green: 0.36, blue: 0.72, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        let label = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: selected ? .semibold : .regular),
            .foregroundColor: selected ? NSColor.white : NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        let height = label.size().height
        label.draw(in: NSRect(x: 10, y: (bounds.height - height) / 2, width: max(0, bounds.width - 40), height: height))
    }
    @objc private func selectAction() { selectTab?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        NSEvent.modifierFlags.contains(.command) ? .move : .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        receiveFiles?(urls, NSEvent.modifierFlags.contains(.command))
        return true
    }
}

func horizontal(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    return stack
}

func inset(_ child: NSView, x: CGFloat = 12, y: CGFloat = 8) -> NSView {
    let container = FlippedView()
    child.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(child)
    NSLayoutConstraint.activate([
        child.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: x),
        child.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -x),
        child.topAnchor.constraint(equalTo: container.topAnchor, constant: y),
        child.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -y)
    ])
    return container
}

func divider() -> NSBox {
    let box = NSBox(); box.boxType = .separator; return box
}
