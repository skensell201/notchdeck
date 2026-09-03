import Foundation
import NotchCore
import Testing
@testable import SettingsUI

private let media = ModuleID("media")
private let shelf = ModuleID("shelf")
private let clipboard = ModuleID("clipboard")
/// A module a newer build has and this one does not — the downgrade case the
/// layout was built to survive.
private let future = ModuleID("from-the-future")

private let descriptors = [
    SettingsModuleDescriptor(id: media, title: "Media", symbolName: "play.circle"),
    SettingsModuleDescriptor(id: shelf, title: "Shelf", symbolName: "tray"),
    SettingsModuleDescriptor(id: clipboard, title: "Clipboard", symbolName: "doc.on.clipboard")
]

/// Records what the view model wrote, so a test can check the layout that would
/// be persisted rather than only the one held in memory.
@MainActor
private final class Recorder {
    var written: [ModuleLayout] = []
    var last: ModuleLayout? { written.last }
}

@MainActor
private func makeModel(
    layout: ModuleLayout = ModuleLayout(order: [media, shelf, clipboard]),
    descriptors: [SettingsModuleDescriptor] = descriptors,
    recorder: Recorder = Recorder()
) -> (ModulesViewModel, Recorder) {
    let model = ModulesViewModel(descriptors: descriptors, layout: layout) { recorder.written.append($0) }
    return (model, recorder)
}

@MainActor
@Suite("Modules settings")
struct ModulesViewModelTests {
    @Test("rows follow the stored order and carry what the list draws")
    func rowsDescribeEachModule() {
        let (model, _) = makeModel(layout: ModuleLayout(order: [shelf, media, clipboard], disabled: [media]))

        #expect(model.rows.map(\.id) == [shelf, media, clipboard])
        #expect(model.rows.map(\.position) == [0, 1, 2])
        #expect(model.rows.map(\.title) == ["Shelf", "Media", "Clipboard"])
        #expect(model.rows.map(\.symbolName) == ["tray", "play.circle", "doc.on.clipboard"])
        #expect(model.rows.map(\.isEnabled) == [true, false, true])
    }

    @Test("a module the layout has never seen is appended, so a new build's module shows up")
    func newModuleIsRegistered() {
        let (model, _) = makeModel(layout: ModuleLayout(order: [clipboard]))

        #expect(model.rows.map(\.id) == [clipboard, media, shelf])
    }

    @Test("moving a module to the front reorders the layout and writes it")
    func moveToFront() {
        let (model, recorder) = makeModel()

        model.move(clipboard, toRow: 0)

        #expect(model.rows.map(\.id) == [clipboard, media, shelf])
        #expect(recorder.last?.order == [clipboard, media, shelf])
    }

    @Test("moving a module to the end puts it last")
    func moveToEnd() {
        let (model, recorder) = makeModel()

        model.move(media, toRow: 2)

        #expect(model.rows.map(\.id) == [shelf, clipboard, media])
        #expect(recorder.last?.order == [shelf, clipboard, media])
    }

    @Test("a destination past the last row clamps to the end rather than being refused")
    func moveBeyondTheEnd() {
        let (model, _) = makeModel()

        model.move(media, toRow: 99)

        #expect(model.rows.map(\.id) == [shelf, clipboard, media])
    }

    @Test("a negative destination clamps to the front")
    func moveBeforeTheStart() {
        let (model, _) = makeModel()

        model.move(clipboard, toRow: -4)

        #expect(model.rows.map(\.id) == [clipboard, media, shelf])
    }

    @Test("a module this build does not have is neither shown nor lost when the order changes")
    func unknownModuleSurvivesAReorder() {
        let (model, recorder) = makeModel(layout: ModuleLayout(order: [media, future, shelf, clipboard]))

        #expect(model.rows.map(\.id) == [media, shelf, clipboard])

        model.move(clipboard, toRow: 0)

        #expect(model.rows.map(\.id) == [clipboard, media, shelf])
        #expect(recorder.last?.order.contains(future) == true)
        // Still between the two modules it was stored between, so the build that
        // knows it puts it back where the user left it.
        #expect(recorder.last?.order == [clipboard, media, future, shelf])
    }

    @Test("a module this build does not have survives being moved past, even as the last entry")
    func unknownModuleSurvivesAMoveToTheEnd() {
        // Only two known modules, so the unknown one is what a move to the last
        // row has to step over.
        let (model, recorder) = makeModel(
            layout: ModuleLayout(order: [media, shelf, future]),
            descriptors: Array(descriptors.prefix(2))
        )

        model.move(media, toRow: 1)

        #expect(model.rows.map(\.id) == [shelf, media])
        #expect(recorder.last?.order == [shelf, future, media])
    }

    @Test("a module this build does not have survives a switch being flipped")
    func unknownModuleSurvivesAToggle() {
        let (model, recorder) = makeModel(layout: ModuleLayout(order: [media, future, shelf, clipboard]))

        model.setEnabled(false, for: shelf)

        #expect(recorder.last?.order == [media, future, shelf, clipboard])
        #expect(recorder.last?.disabled == [shelf])
    }

    @Test("switching a module off hides it from the notch but keeps its row and its place")
    func disablingKeepsTheRow() {
        let (model, recorder) = makeModel()

        model.setEnabled(false, for: shelf)

        #expect(model.rows.map(\.id) == [media, shelf, clipboard])
        #expect(model.rows.map(\.isEnabled) == [true, false, true])
        #expect(model.enabledCount == 2)
        #expect(!model.everythingIsDisabled)
        #expect(recorder.last?.enabledOrder == [media, clipboard])
    }

    @Test("switching every module off is allowed, and the tab knows to say so")
    func disablingEverythingIsAllowed() {
        let (model, recorder) = makeModel()

        for id in [media, shelf, clipboard] {
            model.setEnabled(false, for: id)
        }

        #expect(model.enabledCount == 0)
        #expect(model.everythingIsDisabled)
        #expect(model.rows.count == 3)
        #expect(recorder.last?.enabledOrder.isEmpty == true)
        // The order is untouched, so switching one back on puts it where it was.
        #expect(recorder.last?.order == [media, shelf, clipboard])
    }

    @Test("switching a module back on restores its position rather than appending it")
    func enablingRestoresThePosition() {
        let (model, recorder) = makeModel(layout: ModuleLayout(order: [media, shelf, clipboard], disabled: [shelf]))

        model.setEnabled(true, for: shelf)

        #expect(recorder.last?.enabledOrder == [media, shelf, clipboard])
    }

    @Test("a drag downwards lands where the list says it does")
    func dragDownwards() {
        let (model, _) = makeModel()

        // What `List` reports for dragging row 0 below row 1.
        model.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)

        #expect(model.rows.map(\.id) == [shelf, media, clipboard])
    }

    @Test("a drag upwards lands where the list says it does")
    func dragUpwards() {
        let (model, _) = makeModel()

        model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        #expect(model.rows.map(\.id) == [clipboard, media, shelf])
    }

    @Test("a move that changes nothing is not written")
    func noOpMoveIsNotWritten() {
        let (model, recorder) = makeModel()

        model.move(media, toRow: 0)

        #expect(recorder.written.isEmpty)
    }

    @Test("a module this build does not have cannot be dragged or switched, because it has no row")
    func unknownModuleCannotBeEdited() {
        let (model, recorder) = makeModel(layout: ModuleLayout(order: [media, future, shelf, clipboard]))

        model.move(future, toRow: 0)
        model.setEnabled(false, for: future)

        #expect(recorder.written.isEmpty)
        #expect(model.layout.order == [media, future, shelf, clipboard])
    }
}
