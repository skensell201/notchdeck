import Foundation
import Observation
import Support

/// The shelf's contents and every rule about them. Disk and bookmarks are
/// injected, so this is tested entirely in memory.
@MainActor
@Observable
public final class ShelfStore {
    public private(set) var items: [ShelfItem] = []

    private let persistence: any ShelfPersisting
    private let resolver: any ShelfFileResolving
    private let capacity: Int
    private let logger = Log.make("shelf")

    public init(persistence: any ShelfPersisting, resolver: any ShelfFileResolving, capacity: Int = 40) {
        self.persistence = persistence
        self.resolver = resolver
        self.capacity = capacity
    }

    /// Loads what was saved and re-resolves every bookmark. A file that no longer
    /// resolves is kept and marked unavailable, never silently dropped.
    public func load() {
        let stored: [ShelfItem]
        do {
            stored = try persistence.load()
        } catch {
            logger.error("could not load the shelf: \(error.localizedDescription, privacy: .public)")
            items = []
            return
        }
        items = stored.map(refreshed)
    }

    /// Adds files to the front. A file already on the shelf is moved to the front
    /// instead of duplicated; anything that cannot be bookmarked is skipped.
    public func add(_ urls: [URL]) {
        var added: [ShelfItem] = []
        for url in urls {
            guard let bookmark = try? resolver.bookmark(for: url) else {
                logger.notice("skipping a file that could not be bookmarked: \(url.lastPathComponent, privacy: .public)")
                continue
            }
            let item = ShelfItem(bookmark: bookmark, name: url.lastPathComponent, resolvedPath: url.path)
            added.append(refreshed(item))
        }
        guard !added.isEmpty else { return }

        let incomingPaths = Set(added.map(\.resolvedPath))
        var remaining = items.filter { !incomingPaths.contains($0.resolvedPath) }
        remaining.insert(contentsOf: added, at: 0)
        items = Array(remaining.prefix(capacity))
        save()
    }

    public func remove(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func move(_ id: ShelfItem.ID, to index: Int) {
        guard let current = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: current)
        items.insert(item, at: min(max(index, 0), items.count))
        save()
    }

    public func clear() {
        items = []
        save()
    }

    public func url(for item: ShelfItem) -> URL? {
        if case .available(let url, _, _, _) = resolver.resolve(item.bookmark) { return url }
        return nil
    }

    private func refreshed(_ item: ShelfItem) -> ShelfItem {
        var item = item
        switch resolver.resolve(item.bookmark) {
        case .available(let url, let name, let byteCount, let contentType):
            item.name = name
            item.resolvedPath = url.path
            item.byteCount = byteCount
            item.contentType = contentType
            item.isAvailable = true
        case .unavailable:
            item.isAvailable = false
        }
        return item
    }

    private func save() {
        do {
            try persistence.save(items)
        } catch {
            logger.error("could not save the shelf: \(error.localizedDescription, privacy: .public)")
        }
    }
}
