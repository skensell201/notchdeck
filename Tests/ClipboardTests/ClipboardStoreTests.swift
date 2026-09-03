import Foundation
import Testing
@testable import Clipboard

final class MemoryClipboardPersistence: ClipboardPersisting, @unchecked Sendable {
    var saved: [ClipboardEntry]?
    var loadResult: [ClipboardEntry] = []

    func load() throws -> [ClipboardEntry] { loadResult }
    func save(_ entries: [ClipboardEntry]) throws { saved = entries }
}

@MainActor
@Suite("Clipboard store")
struct ClipboardStoreTests {
    private func makeStore(
        capacity: Int = 20,
        excluding: Set<String> = []
    ) -> (ClipboardStore, MemoryClipboardPersistence) {
        let persistence = MemoryClipboardPersistence()
        let store = ClipboardStore(persistence: persistence, capacity: capacity, excludedBundleIdentifiers: excluding)
        return (store, persistence)
    }

    private func text(_ value: String, from bundle: String? = "com.apple.TextEdit") -> ClipboardCandidate {
        ClipboardCandidate(content: .text(value), sourceBundleIdentifier: bundle)
    }

    @Test("copying text records it")
    func recordsText() {
        let (store, _) = makeStore()

        #expect(store.record(text("hello")))
        #expect(store.entries.count == 1)
    }

    @Test("a password manager's concealed copy is never recorded")
    func concealedIsRejected() {
        let (store, _) = makeStore()
        var candidate = text("hunter2")
        candidate.isConcealed = true

        #expect(!store.record(candidate))
        #expect(store.entries.isEmpty)
    }

    @Test("a transient copy is never recorded")
    func transientIsRejected() {
        let (store, _) = makeStore()
        var candidate = text("scratch")
        candidate.isTransient = true

        #expect(!store.record(candidate))
        #expect(store.entries.isEmpty)
    }

    @Test("a copy from an excluded app is never recorded")
    func excludedAppIsRejected() {
        let (store, _) = makeStore(excluding: ["com.agilebits.onepassword7"])

        #expect(!store.record(text("secret", from: "com.agilebits.onepassword7")))
        #expect(store.entries.isEmpty)
    }

    @Test("empty and whitespace-only text is not worth keeping")
    func blankTextIsRejected() {
        let (store, _) = makeStore()

        #expect(!store.record(text("   \n ")))
        #expect(store.entries.isEmpty)
    }

    @Test("re-copying the same content promotes it instead of duplicating it")
    func duplicatePromotes() {
        let (store, _) = makeStore()
        _ = store.record(text("one"))
        _ = store.record(text("two"))

        #expect(store.record(text("one")))

        #expect(store.entries.count == 2)
        if case .text(let first) = store.entries[0].content { #expect(first == "one") } else { Issue.record("expected text") }
    }

    @Test("the newest copy is first")
    func newestFirst() {
        let (store, _) = makeStore()
        _ = store.record(text("older"))
        _ = store.record(text("newer"))

        if case .text(let first) = store.entries[0].content { #expect(first == "newer") } else { Issue.record("expected text") }
    }

    @Test("exceeding the capacity evicts the oldest unpinned entry")
    func capacityEvictsOldest() {
        let (store, _) = makeStore(capacity: 2)
        _ = store.record(text("1"))
        _ = store.record(text("2"))

        _ = store.record(text("3"))

        #expect(store.entries.count == 2)
        #expect(!store.entries.contains { $0.content == .text("1") })
    }

    @Test("a pinned entry is never evicted, even when it is the oldest")
    func pinnedSurvivesEviction() {
        let (store, _) = makeStore(capacity: 2)
        _ = store.record(text("keep me"))
        store.togglePin(store.entries[0].id)
        _ = store.record(text("2"))

        _ = store.record(text("3"))

        #expect(store.entries.contains { $0.content == .text("keep me") })
        #expect(!store.entries.contains { $0.content == .text("2") })
    }

    @Test("pinning is a toggle")
    func pinToggles() {
        let (store, _) = makeStore()
        _ = store.record(text("x"))
        let id = store.entries[0].id

        store.togglePin(id)
        #expect(store.entries[0].isPinned)

        store.togglePin(id)
        #expect(!store.entries[0].isPinned)
    }

    @Test("removing drops just that entry")
    func remove() {
        let (store, _) = makeStore()
        _ = store.record(text("a"))
        _ = store.record(text("b"))

        store.remove(store.entries[0].id)

        #expect(store.entries.map(\.content) == [.text("a")])
    }

    @Test("clearing keeps pinned entries, because pinning is how the user says keep this")
    func clearKeepsPinned() {
        let (store, _) = makeStore()
        _ = store.record(text("pinned"))
        store.togglePin(store.entries[0].id)
        _ = store.record(text("loose"))

        store.clear()

        #expect(store.entries.map(\.content) == [.text("pinned")])
    }

    @Test("search matches text case-insensitively and ignores non-matching entries")
    func search() {
        let (store, _) = makeStore()
        _ = store.record(text("Hello World"))
        _ = store.record(text("goodbye"))

        #expect(store.entries(matching: "hello").map(\.content) == [.text("Hello World")])
        #expect(store.entries(matching: "").count == 2)
    }

    @Test("images are recorded in memory but never written to disk")
    func imagesAreNotPersisted() {
        let (store, persistence) = makeStore()
        _ = store.record(ClipboardCandidate(content: .image(Data([0xFF, 0xD8])), sourceBundleIdentifier: "com.apple.Preview"))
        _ = store.record(text("text survives"))

        #expect(store.entries.count == 2)
        #expect(persistence.saved?.count == 1)
        #expect(persistence.saved?.first?.content == .text("text survives"))
    }

    @Test("loading restores what was saved")
    func loadRestores() {
        let (store, persistence) = makeStore()
        persistence.loadResult = [ClipboardEntry(content: .text("from disk"), sourceBundleIdentifier: nil)]

        store.load()

        #expect(store.entries.map(\.content) == [.text("from disk")])
    }

    @Test("a load failure leaves an empty, usable history")
    func loadFailureIsEmpty() {
        struct Broken: ClipboardPersisting {
            func load() throws -> [ClipboardEntry] { throw CocoaError(.fileReadCorruptFile) }
            func save(_ entries: [ClipboardEntry]) throws {}
        }
        let store = ClipboardStore(persistence: Broken(), capacity: 5, excludedBundleIdentifiers: [])

        store.load()
        _ = store.record(text("still works"))

        #expect(store.entries.count == 1)
    }
}
