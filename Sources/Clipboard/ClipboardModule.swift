import AppKit
import NotchCore
import NotchUI
import Observation
import SwiftUI
import Support

@MainActor
@Observable
public final class ClipboardModule: NotchModule {
    public static let id = ModuleID("clipboard")
    public let title = "Clipboard"
    public let symbolName = "doc.on.clipboard"

    public let store: ClipboardStore
    public var query: String = ""

    private let pasteboard: any PasteboardWatching
    private let interval: Duration
    private let logger = Log.make("clipboard")
    private var pollTask: Task<Void, Never>?
    private var lastChangeCount: Int

    public init(
        store: ClipboardStore? = nil,
        pasteboard: any PasteboardWatching = SystemPasteboard(),
        interval: Duration = .milliseconds(400)
    ) {
        self.store = store ?? ClipboardStore(persistence: DiskClipboardPersistence.inApplicationSupport())
        self.pasteboard = pasteboard
        self.interval = interval
        self.lastChangeCount = pasteboard.changeCount
        self.store.load()
    }

    // MARK: NotchModule

    /// There is no notification for pasteboard changes, so watching means polling
    /// — and polling only while the panel is open, so a closed notch costs nothing.
    public func activate() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: self?.interval ?? .milliseconds(400))
            }
        }
    }

    public func deactivate() {
        pollTask?.cancel()
        pollTask = nil
    }

    public var hasLiveContent: Bool { false }
    public func peekView() -> AnyView? { nil }
    public func expandedView() -> AnyView { AnyView(ClipboardView(module: self)) }

    // MARK: Actions

    public func copyBack(_ entry: ClipboardEntry) {
        pasteboard.write(entry.content)
        // Our own write bumps the change count; absorb it so the next poll does
        // not re-record what we just put there.
        lastChangeCount = pasteboard.changeCount
    }

    public var visibleEntries: [ClipboardEntry] {
        store.entries(matching: query)
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let candidate = pasteboard.read() else { return }
        store.record(candidate)
    }
}
