# NotchDeck P1b — Shelf and AirDrop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A file shelf in the notch: drag files onto the notch to keep them, drag them back out to Finder or any app, act on them (reveal, Quick Look, copy, remove), and hand them to AirDrop from a dedicated drop zone — persisted across launches.

**Architecture:** The panel's `NotchContainerView` becomes the single AppKit drag destination for the whole notch; it turns `draggingEntered`/`Exited`/`performDragOperation` into three callbacks the app routes to the notch controller (`.dragEntered` / `.dragExited`, which P0's reducer already handles) and to the shelf. `ShelfStore` is pure logic over injected persistence and file-resolution seams, tested without touching the disk. Items are stored as file bookmarks, which survive moves and renames; an item is marked unavailable only when its bookmark genuinely cannot resolve. Drag-out uses the item's real file URL through SwiftUI's `draggable` — file promises are unnecessary when the file already exists. AirDrop is `NSSharingService(named: .sendViaAirDrop)` over a rect the shelf view publishes, in the same way the shell already publishes its presented rect.

**Tech Stack:** Swift 6, SwiftPM, swift-testing, SwiftUI, AppKit drag and drop (`NSDraggingDestination`), `URL.bookmarkData`, `NSSharingService`, `QLPreviewPanel`.

**Spec:** [`docs/superpowers/specs/2026-09-02-p1-media-and-shelf-design.md`](../specs/2026-09-02-p1-media-and-shelf-design.md), section 4.

---

## Background the implementer needs

P1a is merged. What exists:

- `NotchModule` (in `NotchUI`): `id`, `title`, `symbolName`, `activate()`, `deactivate()`, `expandedView()`, `peekView()`, `hasLiveContent`. `ModuleRegistry` registers modules, owns `selection`, reconciles activation on `select` and `setPanelVisible`. `MediaModule` is the only conformer and the template to follow.
- `NotchContainerView` (in `NotchWindow`): flipped, `acceptsFirstMouse`, `hitTest` rejecting points outside `interactiveRect`, which tracks the drawn shape per animation frame via `NotchViewModel.presentedRectInView` → `onPresentedRectChange`. **Drag destinations are hit-tested the same way**, so while the notch is collapsed only the notch itself accepts a drag, and once it opens the whole panel does. That is exactly the behaviour we want.
- `NotchSurface` owns one panel + container + model per display; `NotchSurfaceManager` builds them and applies a shared mode; `AppDelegate` wires everything.
- The notch reducer already handles `.dragEntered` (opens from closed/peek) and `.dragExited` (arms the exit grace when the pointer is outside). Nothing sends them yet.
- `NotchViewModel.openSize` is 620×150.

**The risk this plan exists to retire first:** nobody has verified that a non-activating, never-key panel receives drag events at all. Task 1 is the spike, built as the real minimal feature, and it ends with a human dragging a file. If it fails, stop — the panel configuration has to change before anything else is built.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Sources/NotchWindow/NotchContainerView.swift` | Drag destination: enter/exit/drop callbacks |
| `Sources/NotchWindow/NotchSurface.swift` | Forwards the container's drag callbacks |
| `Sources/NotchWindow/NotchSurfaceManager.swift` | One drag-handling seam for all surfaces |
| `Sources/Shelf/ShelfItem.swift` | The stored reference |
| `Sources/Shelf/ShelfStore.swift` | Pure add/remove/reorder/dedupe/cap/persist logic |
| `Sources/Shelf/ShelfPersistence.swift` | JSON on disk + bookmark resolution, behind protocols |
| `Sources/Shelf/ShelfModule.swift` | The `NotchModule` |
| `Sources/Shelf/ShelfView.swift` | Items grid, empty state, AirDrop zone, actions |
| `Sources/Shelf/ShelfItemView.swift` | One tile: icon, name, drag source, context actions |
| `Sources/Shelf/AirDropZone.swift` | The drop target and its published rect |
| `Sources/Shelf/QuickLook.swift` | `QLPreviewPanel` glue |
| `Tests/ShelfTests/ShelfStoreTests.swift` | Store logic |
| `Tests/ShelfTests/ShelfItemTests.swift` | Item identity and coding |

`Shelf` is a new library target depending on `NotchCore`, `NotchUI`, `Support`. `NotchDeckApp` gains it.

---

## Task 1: The drop spike — a file lands on the notch

**Files:**
- Modify: `Sources/NotchWindow/NotchContainerView.swift`
- Modify: `Sources/NotchWindow/NotchSurface.swift`
- Modify: `Sources/NotchWindow/NotchSurfaceManager.swift`
- Modify: `Sources/NotchDeckApp/AppDelegate.swift`
- Modify: `Package.swift`
- Create: `Sources/Shelf/ShelfModule.swift` (minimal)

This task is deliberately end-to-end and deliberately thin: it proves the panel receives drags, and nothing more.

- [ ] **Step 1: Make the container a drag destination**

In `NotchContainerView`, add three callbacks and the `NSDraggingDestination` overrides:

```swift
    /// Drag-and-drop, forwarded to whoever owns this surface. The container is
    /// the single drag destination for the notch: AppKit picks the deepest view
    /// registered for the dragged types, and a SwiftUI `.onDrop` inside the
    /// hosting view would win that contest and steal the enter/exit events the
    /// notch needs to open itself.
    public var onDragEntered: (() -> Void)?
    public var onDragExited: (() -> Void)?
    /// Receives the dropped file URLs and the drop location in this view's
    /// (flipped) coordinate space. Returns whether the drop was accepted.
    public var onDrop: (([URL], CGPoint) -> Bool)?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard Self.fileURLs(in: sender)?.isEmpty == false else { return [] }
        onDragEntered?()
        return .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragExited?()
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = Self.fileURLs(in: sender), !urls.isEmpty else { return false }
        let location = convert(sender.draggingLocation, from: nil)
        return onDrop?(urls, location) ?? false
    }

    private static func fileURLs(in info: any NSDraggingInfo) -> [URL]? {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
```

`draggingExited` fires when the drag leaves *this view*; because the interactive rect grows when the notch opens, a drag that entered on the collapsed notch stays inside the container as the panel expands under it. Verify that assumption in Step 5.

- [ ] **Step 2: Forward through the surface and manager**

`NotchSurface` gets `public var onDragEntered: (() -> Void)?`, `onDragExited`, and `onDrop: (([URL]) -> Bool)?`, assigned onto the container in `init`. The drop location is not forwarded yet — Task 6 adds it for the AirDrop zone.

`NotchSurfaceManager` gets the same three properties and assigns them to every surface it creates, in both the initial build and `rebuild()`.

- [ ] **Step 3: A minimal shelf module**

`Package.swift`: add `.target(name: "Shelf", dependencies: ["NotchCore", "NotchUI", "Support"])`, `.testTarget(name: "ShelfTests", dependencies: ["Shelf"])`, and `"Shelf"` to `NotchDeckApp`.

`Sources/Shelf/ShelfModule.swift`, minimal on purpose — Task 4 replaces its internals:

```swift
import NotchCore
import NotchUI
import Observation
import SwiftUI

@MainActor
@Observable
public final class ShelfModule: NotchModule {
    public static let id = ModuleID("shelf")
    public let title = "Shelf"
    public let symbolName = "tray.full"

    public private(set) var droppedNames: [String] = []

    public init() {}

    public func activate() {}
    public func deactivate() {}
    public var hasLiveContent: Bool { false }
    public func peekView() -> AnyView? { nil }

    public func expandedView() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                if droppedNames.isEmpty {
                    Text("Drop files here")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    ForEach(droppedNames, id: \.self) { name in
                        Text(name).font(.system(size: 11)).foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 8)
        )
    }

    public func accept(_ urls: [URL]) -> Bool {
        droppedNames.append(contentsOf: urls.map(\.lastPathComponent))
        return true
    }
}
```

The `ShelfTests` target needs at least one file to build: add `Tests/ShelfTests/ShelfSmokeTests.swift` with a single passing `@Test` that `ShelfModule.id.rawValue == "shelf"`. Task 3 adds the real tests.

- [ ] **Step 4: Wire it**

In `AppDelegate.applicationDidFinishLaunching`, after the media module is registered:

```swift
        let shelf = ShelfModule()
        registry.register(shelf)
        self.shelf = shelf
```

and after the surface manager exists:

```swift
        surfaces.onDragEntered = { [weak self] in
            // Open the notch and land the drag on the shelf, whichever tab was
            // showing — a dragged file has exactly one sensible destination.
            self?.controller.send(.dragEntered)
            registry.select(ShelfModule.id)
        }
        surfaces.onDragExited = { [weak self] in
            self?.controller.send(.dragExited)
        }
        surfaces.onDrop = { urls in
            shelf.accept(urls)
        }
```

Add `private var shelf: ShelfModule?` to the delegate.

- [ ] **Step 5: Build, run, and hand it to a human**

```bash
swift build && swift test
./Scripts/run.sh
```

Then a person, at the screen:

- [ ] Drag a file from Finder onto the collapsed notch. The notch opens and switches to the Shelf tab while the drag is still in progress.
- [ ] Keep dragging inside the open panel; it stays open. Drag out of the panel without dropping; it closes after the grace period.
- [ ] Drop a file inside the panel; its name appears in the list.
- [ ] Drop two files at once; both names appear.
- [ ] Drag a file onto the *media* tab's area while the panel is open; the tab switches to Shelf and the drop still lands.

If the first item fails — nothing happens when a file is dragged over the notch — **stop here and report**. The most likely causes, in order: the drag never reaches the container because `hitTest` rejects the point (check `interactiveRect` while collapsed); the panel's `.nonactivatingPanel` style rejects drags (test by temporarily removing it); the hosting view intercepts (test by temporarily setting `hosting.unregisterDraggedTypes()`).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: accept file drags on the notch"
```

---

## Task 2: Shelf items

**Files:**
- Create: `Sources/Shelf/ShelfItem.swift`
- Test: `Tests/ShelfTests/ShelfItemTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter ShelfItemTests`
Expected: FAIL — `cannot find 'ShelfItem' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
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
```

- [ ] **Step 4: Run the tests, then commit**

```bash
swift test --filter ShelfItemTests
git add Sources/Shelf/ShelfItem.swift Tests/ShelfTests/ShelfItemTests.swift
git commit -m "feat: add the shelf item model"
```

---

## Task 3: The shelf store

**Files:**
- Create: `Sources/Shelf/ShelfStore.swift`
- Create: `Sources/Shelf/ShelfPersistence.swift` (protocols only in this task)
- Test: `Tests/ShelfTests/ShelfStoreTests.swift`

All disk and bookmark work sits behind two protocols so the store's logic is tested with in-memory fakes.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter ShelfStoreTests`
Expected: FAIL — `cannot find 'ShelfPersisting' in scope`.

- [ ] **Step 3: Write the seams**

`Sources/Shelf/ShelfPersistence.swift`:

```swift
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
```

- [ ] **Step 4: Write the store**

`Sources/Shelf/ShelfStore.swift`:

```swift
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

    /// Loads what was saved and re-resolves every bookmark. A file that no
    /// longer resolves is kept and marked unavailable, never silently dropped.
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

    /// Adds files to the front. A file already on the shelf is moved to the
    /// front instead of duplicated; anything that cannot be bookmarked is skipped.
    public func add(_ urls: [URL]) {
        var added: [ShelfItem] = []
        for url in urls {
            guard let bookmark = try? resolver.bookmark(for: url) else {
                logger.notice("skipping a file that could not be bookmarked: \(url.lastPathComponent, privacy: .public)")
                continue
            }
            var item = ShelfItem(bookmark: bookmark, name: url.lastPathComponent, resolvedPath: url.path)
            item = refreshed(item)
            added.append(item)
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
```

Note the ordering in `add`: inserting `added` at 0 means a single drop keeps its own order — the first file dropped is the first tile — while a later drop still lands ahead of an earlier one. `addIsDeduplicatedAndPromotes`, `newestFirst` and `moveReorders` pin all three halves.

- [ ] **Step 5: Run the tests, then commit**

```bash
swift test --filter Shelf
git add Sources/Shelf Tests/ShelfTests
git commit -m "feat: add the shelf store"
```

---

## Task 4: Real persistence and bookmarks

**Files:**
- Modify: `Sources/Shelf/ShelfPersistence.swift`
- Modify: `Sources/Shelf/ShelfModule.swift`

No new unit tests: this is the thin layer over `FileManager` and `URL.bookmarkData` that the fakes stand in for.

- [ ] **Step 1: Disk persistence**

Append to `ShelfPersistence.swift`:

```swift
/// A JSON document in Application Support, written atomically.
public struct DiskShelfPersistence: ShelfPersisting {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func inApplicationSupport(bundleIdentifier: String = "com.skensell.notchdeck") -> DiskShelfPersistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DiskShelfPersistence(fileURL: base.appending(path: bundleIdentifier).appending(path: "shelf.json"))
    }

    public func load() throws -> [ShelfItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([ShelfItem].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ items: [ShelfItem]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
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
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else {
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
```

- [ ] **Step 2: Give the module a real store**

`ShelfModule` gains `public let store: ShelfStore`, constructed in `init` with `DiskShelfPersistence.inApplicationSupport()` and `FileBookmarkResolver()`, and calls `store.load()` in `init`. `accept(_:)` becomes `store.add(urls); return true`. Drop `droppedNames`; the placeholder list in `expandedView` reads `store.items` for now — Task 5 replaces the view.

- [ ] **Step 3: Build, run, check persistence**

Drop a file, quit, relaunch, open the shelf: the file is still there. Move the file in Finder, relaunch: still there, new name if renamed. Delete it, relaunch: still listed, marked unavailable (the placeholder list can print `(missing)` after the name for now).

- [ ] **Step 4: Commit**

```bash
git add Sources/Shelf
git commit -m "feat: persist the shelf with file bookmarks"
```

---

## Task 5: Shelf view and item tiles

**Files:**
- Create: `Sources/Shelf/ShelfView.swift`
- Create: `Sources/Shelf/ShelfItemView.swift`
- Create: `Sources/Shelf/QuickLook.swift`
- Modify: `Sources/Shelf/ShelfModule.swift`

The panel is 620×150 with a 33pt tab band, so the shelf has roughly 105pt of height: a single horizontal row of tiles that scrolls, an empty state, and a clear button.

- [ ] **Step 1: The tile**

`ShelfItemView.swift`:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItemView: View {
    let item: ShelfItem
    let url: URL?
    let onReveal: () -> Void
    let onQuickLook: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: 44, height: 44)
                .opacity(item.isAvailable ? 1 : 0.35)
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(item.isAvailable ? 0.9 : 0.4))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.06)))
        .contextMenu {
            Button("Reveal in Finder", action: onReveal).disabled(!item.isAvailable)
            Button("Quick Look", action: onQuickLook).disabled(!item.isAvailable)
            Button("Copy", action: onCopy).disabled(!item.isAvailable)
            Divider()
            Button("Remove from Shelf", role: .destructive, action: onRemove)
        }
        // Dragging a tile out hands the real file URL to the destination: Finder
        // copies or moves it, an app opens it. No file promise is needed because
        // the file already exists.
        .draggable(url ?? URL(filePath: "/dev/null")) {
            icon.frame(width: 44, height: 44)
        }
        .help(item.resolvedPath)
    }

    private var icon: some View {
        let image: NSImage = if let url, item.isAvailable {
            NSWorkspace.shared.icon(forFile: url.path)
        } else {
            NSWorkspace.shared.icon(for: .data)
        }
        return Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
    }
}
```

If `.draggable` with a `URL` does not produce a file drag Finder accepts, switch the payload to `NSItemProvider(contentsOf: url)` via `.onDrag` and say so — the Finder drop is the verification.

- [ ] **Step 2: Quick Look**

`QuickLook.swift`:

```swift
import AppKit
import Quartz

/// Shows one file in the system Quick Look panel. The panel is its own window
/// and does not need ours to be key.
@MainActor
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource {
    private var url: URL?

    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { url as NSURL? }
}
```

Add `Quartz` to nothing in `Package.swift` — it is a system framework; `import Quartz` is enough. If `QLPreviewPanel` refuses to appear from an accessory app, fall back to `NSWorkspace.shared.open(url)` and record it in the README checklist.

- [ ] **Step 3: The shelf view**

`ShelfView.swift`:

```swift
import AppKit
import SwiftUI

struct ShelfView: View {
    let module: ShelfModule

    var body: some View {
        if module.store.items.isEmpty {
            empty
        } else {
            content
        }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.35))
            Text("Drop files here to keep them handy")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(module.store.items) { item in
                        ShelfItemView(
                            item: item,
                            url: module.store.url(for: item),
                            onReveal: { module.reveal(item) },
                            onQuickLook: { module.quickLook(item) },
                            onCopy: { module.copy(item) },
                            onRemove: { module.store.remove(item.id) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
            AirDropZone(module: module)
                .frame(width: 84)
        }
        .overlay(alignment: .bottomTrailing) {
            Button("Clear") { module.confirmClear() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

`AirDropZone` is Task 6; for this task, stub it as a `RoundedRectangle` placeholder so the layout is visible, then replace.

- [ ] **Step 4: Module actions**

In `ShelfModule`:

```swift
    private let quickLook = QuickLookPresenter()

    public func expandedView() -> AnyView { AnyView(ShelfView(module: self)) }

    func reveal(_ item: ShelfItem) {
        guard let url = store.url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func quickLook(_ item: ShelfItem) {
        guard let url = store.url(for: item) else { return }
        quickLook.show(url)
    }

    func copy(_ item: ShelfItem) {
        guard let url = store.url(for: item) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear the shelf?"
        alert.informativeText = "The files themselves are not touched."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
        }
    }
```

`NSAlert.runModal` from an accessory app shows a floating alert; verify it appears in front of the notch panel (level 26). If it hides behind, run it via `NSApp.activate()` first.

- [ ] **Step 5: Build, run, check by hand**

- [ ] Tiles show the file's real icon and name; an unavailable file is dimmed.
- [ ] Right-click: Reveal opens Finder at the file; Quick Look shows it; Copy then ⌘V in Finder pastes the file; Remove drops the tile.
- [ ] Drag a tile to the Desktop: Finder copies the file. Drag a tile onto a Mail compose window: it attaches.
- [ ] Clear asks for confirmation and empties the shelf.

- [ ] **Step 6: Commit**

```bash
git add Sources/Shelf
git commit -m "feat: show shelf items with actions and drag-out"
```

---

## Task 6: AirDrop zone

**Files:**
- Create: `Sources/Shelf/AirDropZone.swift`
- Modify: `Sources/Shelf/ShelfModule.swift`
- Modify: `Sources/NotchWindow/NotchSurface.swift`, `Sources/NotchWindow/NotchSurfaceManager.swift`, `Sources/NotchDeckApp/AppDelegate.swift`

Two ways in: drop files straight onto the zone, or click it to send everything on the shelf. Both go through `NSSharingService`.

- [ ] **Step 1: The zone publishes where it is**

The container decides where a drop landed. The zone publishes its frame in the hosting view's coordinate space — the same space as `presentedRectInView`, for the same reason — and the module keeps it:

`AirDropZone.swift`:

```swift
import SwiftUI

struct AirDropZone: View {
    let module: ShelfModule

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "airplayaudio")
                .font(.system(size: 18))
            Text("AirDrop")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(module.isAirDropTargeted ? 1 : 0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.white.opacity(module.isAirDropTargeted ? 0.8 : 0.25))
        )
        .contentShape(Rectangle())
        .onTapGesture { module.airDropAll() }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { module.airDropZoneRect = $0 }
        .help("Drop files here to AirDrop them, or click to send the whole shelf")
    }
}
```

- [ ] **Step 2: The module sends**

In `ShelfModule`:

```swift
    /// Where the AirDrop zone is drawn, in the hosting view's coordinate space.
    /// The container compares drop locations against it.
    var airDropZoneRect: CGRect = .zero
    var isAirDropTargeted = false

    /// Accepts a drop. A drop inside the AirDrop zone is sent, not shelved.
    public func accept(_ urls: [URL], at location: CGPoint) -> Bool {
        isAirDropTargeted = false
        if airDropZoneRect.contains(location) {
            return airDrop(urls)
        }
        store.add(urls)
        return true
    }

    public func dragMoved(to location: CGPoint) {
        isAirDropTargeted = airDropZoneRect.contains(location)
    }

    public func dragEnded() {
        isAirDropTargeted = false
    }

    func airDropAll() {
        let urls = store.items.compactMap { store.url(for: $0) }
        guard !urls.isEmpty else { return }
        _ = airDrop(urls)
    }

    private func airDrop(_ urls: [URL]) -> Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            logger.notice("AirDrop is not available for these items")
            return false
        }
        service.perform(withItems: urls)
        return true
    }
```

Add `private let logger = Log.make("shelf")` and `import Support`.

- [ ] **Step 3: Forward the drop location and drag movement**

`NotchContainerView.draggingUpdated` gains an `onDragMoved: ((CGPoint) -> Void)?` callback fed with `convert(sender.draggingLocation, from: nil)`. `NotchSurface` and `NotchSurfaceManager` forward `onDragMoved` and change `onDrop` to `(([URL], CGPoint) -> Bool)?`. `AppDelegate` wires `surfaces.onDrop = { urls, point in shelf.accept(urls, at: point) }`, `surfaces.onDragMoved = { shelf.dragMoved(to: $0) }`, and calls `shelf.dragEnded()` from `onDragExited`.

Each surface has its own hosting view, so the location the container reports is already in the same space the zone published — no cross-surface conversion is needed.

- [ ] **Step 4: Build, run, check by hand**

- [ ] With AirDrop on and another device nearby: drag a file from Finder onto the zone — the zone highlights while over it — and drop; the AirDrop picker appears with the file.
- [ ] Click the zone with items on the shelf; the picker appears with all of them.
- [ ] Drop onto the zone with AirDrop off: the drop is refused (the dragged icon springs back) and the log says why.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shelf Sources/NotchWindow Sources/NotchDeckApp
git commit -m "feat: add the AirDrop drop zone"
```

---

## Task 7: Wrap up

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-09-02-p1-media-and-shelf-design.md` (section 4.3, drag-out mechanism)

- [ ] **Step 1: Spec amendment**

Section 4.3 says drag-out uses `NSFilePromiseProvider`. It uses the real file URL through SwiftUI `draggable`, because the file already exists and a promise would only add a copy step. Record that.

- [ ] **Step 2: README**

Layout table: add the `Shelf` target. Manual verification: add the Task 1, 4, 5 and 6 hand-check items above, verbatim.

- [ ] **Step 3: Full check**

```bash
swift build && swift test
./Scripts/run.sh
```

Walk the whole shelf checklist once more on the final build, then commit:

```bash
git add README.md docs
git commit -m "docs: record the shelf verification checklist"
```

---

## Out of scope for P1b

- Image compression and zip/unzip on the shelf — not in NotchNook 1.6 either
- Multi-select on tiles — a later polish item; AirDrop-all covers the common case
- Dropping text or images that are not files — the shelf stores files; the clipboard module (P2) covers text
