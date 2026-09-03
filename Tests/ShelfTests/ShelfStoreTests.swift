import Foundation
import Testing
@testable import Shelf

final class MemoryPersistence: ShelfPersisting, @unchecked Sendable {
    var saved: [ShelfItem]? = nil
    var loadResult: [ShelfItem] = []
    var saveCount = 0

    func load() throws -> [ShelfItem] { loadResult }
    func save(_ items: [ShelfItem]) throws {
        saved = items
        saveCount += 1
    }
}

/// Resolves bookmarks from a table the test controls. A bookmark is its path's
/// UTF-8 bytes, so tests can make them by hand.
final class FakeResolver: ShelfFileResolving, @unchecked Sendable {
    var missing: Set<String> = []

    func bookmark(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolve(_ bookmark: Data) -> ShelfResolution {
        let path = String(decoding: bookmark, as: UTF8.self)
        if missing.contains(path) { return .unavailable }
        return .available(URL(filePath: path), name: URL(filePath: path).lastPathComponent, byteCount: 10, contentType: "public.data")
    }
}

@MainActor
@Suite("Shelf store")
struct ShelfStoreTests {
    private func makeStore(capacity: Int = 20) -> (ShelfStore, MemoryPersistence, FakeResolver) {
        let persistence = MemoryPersistence()
        let resolver = FakeResolver()
        return (ShelfStore(persistence: persistence, resolver: resolver, capacity: capacity), persistence, resolver)
    }

    @Test("adding a file appends an available item and saves")
    func addAppendsAndSaves() throws {
        let (store, persistence, _) = makeStore()

        store.add([URL(filePath: "/a/one.txt")])

        #expect(store.items.map(\.name) == ["one.txt"])
        #expect(store.items[0].isAvailable)
        #expect(persistence.saved?.count == 1)
    }

    @Test("adding the same file twice keeps one item and moves it to the front")
    func addIsDeduplicatedAndPromotes() {
        let (store, _, _) = makeStore()
        store.add([URL(filePath: "/a/one.txt"), URL(filePath: "/a/two.txt")])

        store.add([URL(filePath: "/a/one.txt")])

        #expect(store.items.map(\.name) == ["one.txt", "two.txt"])
    }

    @Test("new items go to the front so the latest drop is the first tile")
    func newestFirst() {
        let (store, _, _) = makeStore()
        store.add([URL(filePath: "/a/first.txt")])
        store.add([URL(filePath: "/a/second.txt")])

        #expect(store.items.map(\.name) == ["second.txt", "first.txt"])
    }

    @Test("the shelf drops its oldest item when the capacity is exceeded")
    func capacityEvictsOldest() {
        let (store, _, _) = makeStore(capacity: 2)
        store.add([URL(filePath: "/a/1")])
        store.add([URL(filePath: "/a/2")])

        store.add([URL(filePath: "/a/3")])

        #expect(store.items.map(\.name) == ["3", "2"])
    }

    @Test("removing an item saves the remainder")
    func removeSaves() {
        let (store, persistence, _) = makeStore()
        store.add([URL(filePath: "/a/1"), URL(filePath: "/a/2")])
        let target = store.items[1]

        store.remove(target.id)

        #expect(store.items.map(\.name) == ["1"])
        #expect(persistence.saved?.map(\.name) == ["1"])
    }

    @Test("moving an item reorders and saves")
    func moveReorders() {
        let (store, _, _) = makeStore()
        store.add([URL(filePath: "/a/1"), URL(filePath: "/a/2"), URL(filePath: "/a/3")])

        // A single drop keeps its own order, so the shelf reads 1, 2, 3 and the
        // last tile is "3".
        #expect(store.items.map(\.name) == ["1", "2", "3"])

        store.move(store.items[2].id, to: 0)

        #expect(store.items.map(\.name) == ["3", "1", "2"])
    }

    @Test("loading re-resolves every bookmark and marks the missing ones unavailable, without dropping them")
    func loadMarksMissing() throws {
        let (store, persistence, resolver) = makeStore()
        let gone = ShelfItem(bookmark: Data("/a/gone".utf8), name: "gone", resolvedPath: "/a/gone")
        let here = ShelfItem(bookmark: Data("/a/here".utf8), name: "old-name", resolvedPath: "/old/path")
        persistence.loadResult = [gone, here]
        resolver.missing = ["/a/gone"]

        store.load()

        #expect(store.items.map(\.isAvailable) == [false, true])
        #expect(store.items[1].name == "here")
        #expect(store.items[1].resolvedPath == "/a/here")
    }

    @Test("a load failure leaves an empty, usable shelf rather than crashing")
    func loadFailureIsEmpty() {
        struct Broken: ShelfPersisting {
            func load() throws -> [ShelfItem] { throw CocoaError(.fileReadCorruptFile) }
            func save(_ items: [ShelfItem]) throws {}
        }
        let store = ShelfStore(persistence: Broken(), resolver: FakeResolver(), capacity: 5)

        store.load()
        store.add([URL(filePath: "/a/1")])

        #expect(store.items.count == 1)
    }

    @Test("clearing empties the shelf and saves once")
    func clear() {
        let (store, persistence, _) = makeStore()
        store.add([URL(filePath: "/a/1"), URL(filePath: "/a/2")])
        let before = persistence.saveCount

        store.clear()

        #expect(store.items.isEmpty)
        #expect(persistence.saveCount == before + 1)
    }

    @Test("a URL whose bookmark cannot be made is skipped, and the rest are added")
    func unbookmarkableIsSkipped() {
        final class Picky: ShelfFileResolving, @unchecked Sendable {
            func bookmark(for url: URL) throws -> Data {
                if url.path.hasSuffix("bad") { throw CocoaError(.fileNoSuchFile) }
                return Data(url.path.utf8)
            }
            func resolve(_ bookmark: Data) -> ShelfResolution {
                let path = String(decoding: bookmark, as: UTF8.self)
                return .available(URL(filePath: path), name: URL(filePath: path).lastPathComponent, byteCount: nil, contentType: nil)
            }
        }
        let store = ShelfStore(persistence: MemoryPersistence(), resolver: Picky(), capacity: 5)

        store.add([URL(filePath: "/a/bad"), URL(filePath: "/a/good")])

        #expect(store.items.map(\.name) == ["good"])
    }
}
