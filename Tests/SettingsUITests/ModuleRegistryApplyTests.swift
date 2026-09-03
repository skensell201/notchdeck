import NotchCore
import NotchUI
import SwiftUI
import Testing

/// Counts the activations the registry hands out, so a test can see a module
/// being switched off as well as disappearing from the list.
@MainActor
private class StubModule {
    let symbolName = "circle"
    private(set) var activations = 0
    private(set) var deactivations = 0

    func activate() { activations += 1 }
    func deactivate() { deactivations += 1 }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
    func peekView() -> AnyView? { nil }
    var hasLiveContent: Bool { false }
}

// One class per module, because `NotchModule` identifies a module by a static
// property: a single class parameterised by an identifier would answer with the
// same one for all three instances, which is exactly the shape of bug this file
// is here to catch.
@MainActor private final class MediaStub: StubModule, NotchModule {
    static let id = ModuleID("media")
    let title = "Media"
}

@MainActor private final class ShelfStub: StubModule, NotchModule {
    static let id = ModuleID("shelf")
    let title = "Shelf"
}

@MainActor private final class ClipboardStub: StubModule, NotchModule {
    static let id = ModuleID("clipboard")
    let title = "Clipboard"
}

@MainActor
@Suite("Registry adopting an edited layout")
struct ModuleRegistryApplyTests {
    private let media = MediaStub()
    private let shelf = ShelfStub()
    private let clipboard = ClipboardStub()

    private func makeRegistry() -> ModuleRegistry {
        let registry = ModuleRegistry()
        registry.register(media)
        registry.register(shelf)
        registry.register(clipboard)
        return registry
    }

    @Test("a reorder changes what the panel shows without moving the user off their tab")
    func reorderKeepsTheSelection() {
        let registry = makeRegistry()
        registry.select(ShelfStub.id)

        registry.apply(ModuleLayout(order: [ClipboardStub.id, ShelfStub.id, MediaStub.id]))

        #expect(registry.visibleModules.map(\.id) == [ClipboardStub.id, ShelfStub.id, MediaStub.id])
        #expect(registry.selection == ShelfStub.id)
    }

    @Test("switching off the selected module falls back to the first one still showing")
    func disablingTheSelectionMovesIt() {
        let registry = makeRegistry()
        registry.select(ShelfStub.id)

        registry.apply(ModuleLayout(
            order: [MediaStub.id, ShelfStub.id, ClipboardStub.id],
            disabled: [ShelfStub.id]
        ))

        #expect(registry.selection == MediaStub.id)
        #expect(registry.visibleModules.map(\.id) == [MediaStub.id, ClipboardStub.id])
    }

    @Test("switching everything off leaves nothing selected and nothing running")
    func disablingEverythingDeactivates() {
        let registry = makeRegistry()
        registry.setPanelVisible(true)
        #expect(media.activations == 1)

        registry.apply(ModuleLayout(
            order: [MediaStub.id, ShelfStub.id, ClipboardStub.id],
            disabled: [MediaStub.id, ShelfStub.id, ClipboardStub.id]
        ))

        #expect(registry.selection == nil)
        #expect(registry.visibleModules.isEmpty)
        #expect(media.deactivations == 1)
    }

    @Test("a module this build does not have is kept in the layout the registry holds")
    func unknownModuleIsKept() {
        let registry = makeRegistry()
        let future = ModuleID("from-the-future")

        registry.apply(ModuleLayout(order: [MediaStub.id, future, ShelfStub.id, ClipboardStub.id]))

        #expect(registry.layout.order.contains(future))
        #expect(registry.visibleModules.map(\.id) == [MediaStub.id, ShelfStub.id, ClipboardStub.id])
    }
}
