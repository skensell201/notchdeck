import Foundation

/// A file the user parked on the shelf.
///
/// The bookmark is the identity and the storage: it survives the file being
/// moved or renamed, which a path would not. `resolvedPath` is a cache of where
/// the bookmark last pointed, used for de-duplication and display only.
public struct ShelfItem: Equatable, Sendable, Codable, Identifiable {
    public var id: Data { bookmark }

    public let bookmark: Data
    public var name: String
    public var resolvedPath: String
    public var byteCount: Int64?
    public var contentType: String?
    public var addedAt: Date
    /// False once the bookmark stopped resolving — the file was deleted, or its
    /// volume is not mounted. The item stays on the shelf so the user can see
    /// what is missing and remove it deliberately.
    public var isAvailable: Bool

    public init(bookmark: Data, name: String, resolvedPath: String, addedAt: Date = Date()) {
        self.bookmark = bookmark
        self.name = name
        self.resolvedPath = resolvedPath
        self.addedAt = addedAt
        self.isAvailable = true
    }
}
