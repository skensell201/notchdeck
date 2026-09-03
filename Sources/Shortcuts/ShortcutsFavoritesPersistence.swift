import Foundation

public protocol ShortcutsFavoritesPersisting: Sendable {
    func load() throws -> Set<String>
    func save(_ names: Set<String>) throws
}

/// A JSON document in Application Support, written atomically. Follows the
/// same shape as `DiskShelfPersistence`.
public struct DiskShortcutsFavoritesPersistence: ShortcutsFavoritesPersisting {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func inApplicationSupport(
        bundleIdentifier: String = "com.skensell.notchdeck"
    ) -> DiskShortcutsFavoritesPersistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DiskShortcutsFavoritesPersistence(
            fileURL: base.appending(path: bundleIdentifier).appending(path: "shortcuts-favorites.json")
        )
    }

    public func load() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ names: Set<String>) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(names).write(to: fileURL, options: .atomic)
    }
}
