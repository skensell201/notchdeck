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
