import Testing
@testable import Shelf

@Suite("Shelf module")
struct ShelfSmokeTests {
    // The module is main-actor isolated, so even its static identity has to be
    // read from the main actor.
    @Test("the module identifies itself as the shelf")
    @MainActor
    func moduleID() {
        #expect(ShelfModule.id.rawValue == "shelf")
    }
}
