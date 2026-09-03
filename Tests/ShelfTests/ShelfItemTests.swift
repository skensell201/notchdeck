import Foundation
import Testing
@testable import Shelf

@Suite("Shelf item")
struct ShelfItemTests {
    @Test("an item is identified by its bookmark, not by the path it was resolved to")
    func identityIsTheBookmark() {
        let a = ShelfItem(bookmark: Data([1, 2, 3]), name: "a.txt", resolvedPath: "/x/a.txt")
        let b = ShelfItem(bookmark: Data([1, 2, 3]), name: "renamed.txt", resolvedPath: "/y/renamed.txt")

        #expect(a.id == b.id)
    }

    @Test("items round-trip through JSON with every field intact")
    func codableRoundTrip() throws {
        var item = ShelfItem(bookmark: Data([9, 9]), name: "photo.heic", resolvedPath: "/p/photo.heic")
        item.byteCount = 1_234_567
        item.contentType = "public.heic"
        item.isAvailable = false

        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(ShelfItem.self, from: data)

        #expect(restored == item)
    }

    @Test("a freshly added item is available and dated now")
    func freshItemDefaults() {
        let before = Date()
        let item = ShelfItem(bookmark: Data(), name: "n", resolvedPath: "/n")

        #expect(item.isAvailable)
        #expect(item.addedAt >= before)
    }
}
