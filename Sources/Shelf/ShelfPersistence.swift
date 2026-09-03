import Foundation

public protocol ShelfPersisting: Sendable {
    func load() throws -> [ShelfItem]
    func save(_ items: [ShelfItem]) throws
}

public enum ShelfResolution: Equatable, Sendable {
    case available(URL, name: String, byteCount: Int64?, contentType: String?)
    case unavailable
}

public protocol ShelfFileResolving: Sendable {
    func bookmark(for url: URL) throws -> Data
    func resolve(_ bookmark: Data) -> ShelfResolution
}

/// A JSON document in Application Support, written atomically.
public struct DiskShelfPersistence: ShelfPersisting {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func inApplicationSupport(
        bundleIdentifier: String = "com.skensell.notchdeck"
    ) -> DiskShelfPersistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DiskShelfPersistence(
            fileURL: base.appending(path: bundleIdentifier).appending(path: "shelf.json")
        )
    }

    public func load() throws -> [ShelfItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([ShelfItem].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ items: [ShelfItem]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
    }
}

/// Bookmarks without security scope: NotchDeck is not sandboxed, and a plain
/// bookmark already survives the file being moved or renamed.
public struct FileBookmarkResolver: ShelfFileResolving {
    public init() {}

    public func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ bookmark: Data) -> ShelfResolution {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), FileManager.default.fileExists(atPath: url.path) else {
            return .unavailable
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .nameKey])
        return .available(
            url,
            name: values?.name ?? url.lastPathComponent,
            byteCount: values?.fileSize.map(Int64.init),
            contentType: values?.contentType?.identifier
        )
    }
}
