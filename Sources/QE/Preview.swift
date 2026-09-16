import AppKit
import QuickLookUI

extension BrowserController: QLPreviewPanelDataSource {
    @objc func previewSelected(_ sender: Any?) {
        guard !selected.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, panel.currentController as? BrowserController === self {
            panel.orderOut(nil)
            return
        }
        window?.makeFirstResponder(table)
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        previewURLs = selected
        panel.dataSource = self
        panel.reloadData()
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs.indices.contains(index) ? previewURLs[index] as NSURL : nil
    }

    func updatePreviewController() {
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared()?.updateController() }
    }
    func updatePreview() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
              panel.currentController as? BrowserController === self else { return }
        previewURLs = selected
        panel.reloadData()
    }
    func closePreview() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
              panel.currentController as? BrowserController === self else { return }
        panel.orderOut(nil)
    }
}
