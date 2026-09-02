import Testing
@testable import NotchCore

@Suite("Notch reducer: hover")
struct NotchReducerHoverTests {
    @Test("entering a closed notch arms the dwell timer without opening")
    func enteringArmsDwell() {
        let transition = NotchReducer.reduce(state: .closed, event: .pointerEntered)

        #expect(transition.state.mode == .closed)
        #expect(transition.state.pointerInside)
        #expect(transition.effects == [.scheduleHoverDwell])
    }

    @Test("leaving before the dwell elapses cancels the dwell timer")
    func leavingCancelsDwell() {
        let entered = NotchReducer.reduce(state: .closed, event: .pointerEntered).state
        let transition = NotchReducer.reduce(state: entered, event: .pointerExited)

        #expect(transition.state.mode == .closed)
        #expect(!transition.state.pointerInside)
        #expect(transition.effects == [.cancelHoverDwell])
    }

    @Test("the dwell elapsing while the pointer is inside opens the notch")
    func dwellOpens() {
        let entered = NotchReducer.reduce(state: .closed, event: .pointerEntered).state
        let transition = NotchReducer.reduce(state: entered, event: .hoverDwellElapsed)

        #expect(transition.state.mode == .open)
    }

    @Test("a stale dwell that fires after the pointer left does nothing")
    func staleDwellIsIgnored() {
        var state = NotchReducer.reduce(state: .closed, event: .pointerEntered).state
        state = NotchReducer.reduce(state: state, event: .pointerExited).state
        let transition = NotchReducer.reduce(state: state, event: .hoverDwellElapsed)

        #expect(transition.state.mode == .closed)
    }

    @Test("leaving an open notch starts the grace period instead of closing")
    func leavingOpenStartsGrace() {
        let open = NotchState(mode: .open, pointerInside: true)
        let transition = NotchReducer.reduce(state: open, event: .pointerExited)

        #expect(transition.state.mode == .open)
        #expect(transition.effects == [.scheduleExitGrace])
    }

    @Test("returning during the grace period cancels the close")
    func returningCancelsGrace() {
        let leaving = NotchState(mode: .open, pointerInside: false)
        let transition = NotchReducer.reduce(state: leaving, event: .pointerEntered)

        #expect(transition.state.mode == .open)
        #expect(transition.effects == [.cancelExitGrace])
    }

    @Test("the grace period elapsing with the pointer away closes the notch")
    func graceCloses() {
        let leaving = NotchState(mode: .open, pointerInside: false)
        let transition = NotchReducer.reduce(state: leaving, event: .exitGraceElapsed)

        #expect(transition.state.mode == .closed)
    }

    @Test("a stale grace timer firing after the pointer returned leaves the notch open")
    func staleGraceIsIgnored() {
        let returned = NotchState(mode: .open, pointerInside: true)
        let transition = NotchReducer.reduce(state: returned, event: .exitGraceElapsed)

        #expect(transition.state.mode == .open)
    }
}
