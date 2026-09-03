import Foundation
import Testing
@testable import NotchCore

@Suite("Module layout")
struct ModuleLayoutTests {
    private let media = ModuleID("media")
    private let shelf = ModuleID("shelf")
    private let clipboard = ModuleID("clipboard")

    @Test("a layout lists its modules in the order it was given")
    func preservesOrder() {
        let layout = ModuleLayout(order: [media, shelf, clipboard], disabled: [])

        #expect(layout.enabledOrder == [media, shelf, clipboard])
    }

    @Test("disabled modules keep their place in the order but drop out of the enabled list")
    func disabledDropOut() {
        let layout = ModuleLayout(order: [media, shelf, clipboard], disabled: [shelf])

        #expect(layout.enabledOrder == [media, clipboard])
        #expect(layout.order == [media, shelf, clipboard])
    }

    @Test("moving a module changes its position without disturbing the rest")
    func moving() {
        var layout = ModuleLayout(order: [media, shelf, clipboard], disabled: [])

        layout.move(clipboard, to: 0)

        #expect(layout.order == [clipboard, media, shelf])
    }

    @Test("moving a module that is not in the layout does nothing")
    func movingUnknownIsIgnored() {
        var layout = ModuleLayout(order: [media, shelf], disabled: [])

        layout.move(clipboard, to: 0)

        #expect(layout.order == [media, shelf])
    }

    @Test("registering a module appends it once, however many times it is registered")
    func registerIsIdempotent() {
        var layout = ModuleLayout(order: [media], disabled: [])

        layout.register(shelf)
        layout.register(shelf)

        #expect(layout.order == [media, shelf])
    }

    @Test("a module the user disabled stays disabled when it is registered again")
    func registerPreservesDisabledState() {
        var layout = ModuleLayout(order: [media, shelf], disabled: [shelf])

        layout.register(shelf)

        #expect(layout.enabledOrder == [media])
    }

    @Test("a layout survives a JSON round trip, including modules this build does not know")
    func codableRoundTrip() throws {
        let original = ModuleLayout(order: [media, shelf, ModuleID("from-the-future")], disabled: [shelf])

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ModuleLayout.self, from: data)

        #expect(restored == original)
    }

    @Test("the first enabled module is the default selection, and nil when everything is disabled")
    func defaultSelection() {
        #expect(ModuleLayout(order: [media, shelf], disabled: [media]).defaultSelection == shelf)
        #expect(ModuleLayout(order: [media], disabled: [media]).defaultSelection == nil)
    }
}
