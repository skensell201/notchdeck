import Foundation
import Testing
@testable import Shortcuts

final class MemoryFavoritesPersistence: ShortcutsFavoritesPersisting, @unchecked Sendable {
    var saved: Set<String>?
    var loadResult: Set<String> = []
    var saveCount = 0

    func load() throws -> Set<String> { loadResult }
    func save(_ names: Set<String>) throws {
        saved = names
        saveCount += 1
    }
}

@MainActor
@Suite("Shortcuts favourites store")
struct ShortcutsFavoritesStoreTests {
    private func makeStore(loaded: Set<String> = []) -> (ShortcutsFavoritesStore, MemoryFavoritesPersistence) {
        let persistence = MemoryFavoritesPersistence()
        persistence.loadResult = loaded
        let store = ShortcutsFavoritesStore(persistence: persistence)
        return (store, persistence)
    }

    @Test("pinning a name marks it pinned and saves")
    func pinSaves() {
        let (store, persistence) = makeStore()

        store.togglePin("Focus Mode")

        #expect(store.isPinned("Focus Mode"))
        #expect(persistence.saved == ["Focus Mode"])
        #expect(persistence.saveCount == 1)
    }

    @Test("unpinning a pinned name clears it and saves")
    func unpinSaves() {
        let (store, persistence) = makeStore()
        store.togglePin("Focus Mode")

        store.togglePin("Focus Mode")

        #expect(!store.isPinned("Focus Mode"))
        #expect(persistence.saved == [])
    }

    @Test("load reads whatever persistence returns")
    func loadReadsPersisted() {
        let (store, _) = makeStore(loaded: ["Good Morning"])

        store.load()

        #expect(store.isPinned("Good Morning"))
    }

    @Test("load failure falls back to no pins, not a crash")
    func loadFailureFallsBackToEmpty() {
        struct Failing: ShortcutsFavoritesPersisting {
            func load() throws -> Set<String> { throw CocoaError(.fileReadUnknown) }
            func save(_ names: Set<String>) throws {}
        }
        let store = ShortcutsFavoritesStore(persistence: Failing())

        store.load()

        #expect(store.pinnedNames.isEmpty)
    }

    @Test("pinned names sort first, alphabetically, ahead of the rest")
    func pinnedFirstThenAlphabetical() {
        let (store, _) = makeStore()
        store.togglePin("Zebra")
        store.togglePin("Apple")

        let ordered = store.ordered(["Middle", "Zebra", "Banana", "Apple"])

        #expect(ordered == ["Apple", "Zebra", "Banana", "Middle"])
    }

    @Test("alphabetical ordering is case-insensitive")
    func caseInsensitiveOrdering() {
        let (store, _) = makeStore()

        let ordered = store.ordered(["banana", "Apple", "cherry"])

        #expect(ordered == ["Apple", "banana", "cherry"])
    }

    @Test("a pin on a shortcut absent from the list is remembered but not shown")
    func pinnedButDeletedIsHiddenNotForgotten() {
        let (store, _) = makeStore()
        store.togglePin("Ghost Shortcut")

        let ordered = store.ordered(["Alpha", "Beta"])

        #expect(ordered == ["Alpha", "Beta"])
        // The pin itself survives even though nothing currently shows it —
        // unpinning a deleted shortcut is never required.
        #expect(store.isPinned("Ghost Shortcut"))
    }

    @Test("recreating a shortcut with a still-pinned name brings the pin back")
    func recreatingRestoresPinnedPosition() {
        let (store, _) = makeStore()
        store.togglePin("Ghost Shortcut")
        #expect(store.ordered(["Alpha", "Beta"]) == ["Alpha", "Beta"])

        let ordered = store.ordered(["Alpha", "Beta", "Ghost Shortcut"])

        #expect(ordered == ["Ghost Shortcut", "Alpha", "Beta"])
    }
}
