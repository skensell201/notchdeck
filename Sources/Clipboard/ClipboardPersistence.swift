import Foundation

public protocol ClipboardPersisting: Sendable {
    func load() throws -> [ClipboardEntry]
    func save(_ entries: [ClipboardEntry]) throws
}

/// A JSON document in Application Support, written atomically.
public struct DiskClipboardPersistence: ClipboardPersisting {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func inApplicationSupport(
        bundleIdentifier: String = "com.skensell.notchdeck"
    ) -> DiskClipboardPersistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DiskClipboardPersistence(
            fileURL: base.appending(path: bundleIdentifier).appending(path: "clipboard.json")
        )
    }

    public func load() throws -> [ClipboardEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ entries: [ClipboardEntry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
