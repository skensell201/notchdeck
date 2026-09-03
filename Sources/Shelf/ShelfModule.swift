import AppKit
import NotchCore
import NotchUI
import Observation
import SwiftUI
import Support

@MainActor
@Observable
public final class ShelfModule: NotchModule {
    public static let id = ModuleID("shelf")
    public let title = "Shelf"
    public let symbolName = "tray.full"

    public let store: ShelfStore

    /// Where the AirDrop zone is drawn, in the hosting view's coordinate space —
    /// the same space the container reports drop locations in.
    var airDropZoneRect: CGRect = .zero
    var isAirDropTargeted = false

    private let logger = Log.make("shelf")
    private let quickLookPresenter = QuickLookPresenter()

    public init(store: ShelfStore? = nil) {
        self.store = store ?? ShelfStore(
            persistence: DiskShelfPersistence.inApplicationSupport(),
            resolver: FileBookmarkResolver()
        )
        self.store.load()
    }

    // MARK: NotchModule

    public func activate() {}
    public func deactivate() {}
    public var hasLiveContent: Bool { false }
    public func peekView() -> AnyView? { nil }
    public func expandedView() -> AnyView { AnyView(ShelfView(module: self)) }

    // MARK: Drops

    /// Accepts a drop. A drop inside the AirDrop zone is sent, not shelved.
    public func accept(_ urls: [URL], at location: CGPoint) -> Bool {
        isAirDropTargeted = false
        if airDropZoneRect.contains(location) {
            return airDrop(urls)
        }
        store.add(urls)
        return true
    }

    public func dragMoved(to location: CGPoint) {
        isAirDropTargeted = airDropZoneRect.contains(location)
    }

    public func dragEnded() {
        isAirDropTargeted = false
    }

    // MARK: Item actions

    func reveal(_ item: ShelfItem) {
        guard let url = store.url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func quickLook(_ item: ShelfItem) {
        guard let url = store.url(for: item) else { return }
        quickLookPresenter.show(url)
    }

    func copy(_ item: ShelfItem) {
        guard let url = store.url(for: item) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear the shelf?"
        alert.informativeText = "The files themselves are not touched."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        // The panel floats above the menu bar, so the alert has to be brought in
        // front of it deliberately; an accessory app is never active on its own.
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
        }
    }

    func airDropAll() {
        let urls = store.items.compactMap { store.url(for: $0) }
        guard !urls.isEmpty else { return }
        _ = airDrop(urls)
    }

    private func airDrop(_ urls: [URL]) -> Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            logger.notice("AirDrop is not available for these items")
            return false
        }
        service.perform(withItems: urls)
        return true
    }
}
