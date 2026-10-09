import AppKit
import QuickLookUI

/// The system Quick Look panel for the gallery's selection.
@MainActor
final class GalleryPreview: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = GalleryPreview()
    private var urls: [URL] = []

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func toggle(_ urls: [URL]) {
        let panel = QLPreviewPanel.shared()!
        if isVisible {
            panel.orderOut(nil)
            return
        }
        guard !urls.isEmpty else {
            return
        }
        show(urls)
    }

    /// Shows `urls`, or follows the selection when the panel is already open.
    func show(_ urls: [URL]) {
        self.urls = urls
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
