import AppKit
import Quartz

/// Shows one file in the system Quick Look panel. The panel is its own window and
/// does not need ours to be key — which matters, because ours never is.
/// `QLPreviewPanelDataSource` is not main-actor-isolated, so the type is not either:
/// its two callbacks stay nonisolated and the panel
/// only ever calls them on the main thread. The stored URL is guarded by a lock
/// rather than by the actor for the same reason.
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _url: URL?

    private var url: URL? {
        get { lock.withLock { _url } }
        set { lock.withLock { _url = newValue } }
    }

    @MainActor
    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else {
            NSWorkspace.shared.open(url)
            return
        }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url as NSURL?
    }
}
