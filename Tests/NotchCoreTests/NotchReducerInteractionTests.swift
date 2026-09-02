import Testing
@testable import NotchCore

@Suite("Notch reducer: interaction")
struct NotchReducerInteractionTests {
    @Test("scrolling down over a closed notch opens it immediately")
    func scrollDownOpens() {
        let transition = NotchReducer.reduce(state: .closed, event: .scrolled(.down))

        #expect(transition.state.mode == .open)
        #expect(transition.effects.contains(.cancelHoverDwell))
    }

    @Test("scrolling up over a closed notch does nothing")
    func scrollUpOnClosedIsIgnored() {
        let transition = NotchReducer.reduce(state: .closed, event: .scrolled(.up))

        #expect(transition.state.mode == .closed)
        #expect(transition.effects.isEmpty)
    }

    @Test("scrolling up over an open notch closes it")
    func scrollUpCloses() {
        let open = NotchState(mode: .open, pointerInside: true)
        let transition = NotchReducer.reduce(state: open, event: .scrolled(.up))

        #expect(transition.state.mode == .closed)
        #expect(transition.effects.contains(.cancelExitGrace))
    }

    @Test("horizontal scrolls never change the notch mode")
    func horizontalScrollIsIgnored() {
        let open = NotchState(mode: .open, pointerInside: true)

        #expect(NotchReducer.reduce(state: open, event: .scrolled(.left)).state.mode == .open)
        #expect(NotchReducer.reduce(state: open, event: .scrolled(.right)).state.mode == .open)
    }

    @Test("clicking an open notch pins it")
    func clickPins() {
        let open = NotchState(mode: .open, pointerInside: true)
        let transition = NotchReducer.reduce(state: open, event: .clicked)

        #expect(transition.state.mode == .pinned)
        #expect(transition.effects == [.cancelExitGrace])
    }

    @Test("a pinned notch survives the pointer leaving")
    func pinnedIgnoresExit() {
        let pinned = NotchState(mode: .pinned, pointerInside: true)
        let transition = NotchReducer.reduce(state: pinned, event: .pointerExited)

        #expect(transition.state.mode == .pinned)
        #expect(transition.effects.isEmpty)
    }

    @Test("clicking outside dismisses a pinned notch")
    func clickOutsideDismissesPinned() {
        let pinned = NotchState(mode: .pinned, pointerInside: false)
        let transition = NotchReducer.reduce(state: pinned, event: .clickedOutside)

        #expect(transition.state.mode == .closed)
    }

    @Test("escape dismisses a pinned notch")
    func escapeDismissesPinned() {
        let pinned = NotchState(mode: .pinned, pointerInside: false)
        let transition = NotchReducer.reduce(state: pinned, event: .escapePressed)

        #expect(transition.state.mode == .closed)
    }

    @Test("clicking outside a closed notch does nothing")
    func clickOutsideClosedIsIgnored() {
        let transition = NotchReducer.reduce(state: .closed, event: .clickedOutside)

        #expect(transition.state.mode == .closed)
        #expect(transition.effects.isEmpty)
    }

    @Test("clicking a closed notch opens it")
    func clickOpensClosed() {
        let transition = NotchReducer.reduce(state: .closed, event: .clicked)

        #expect(transition.state.mode == .open)
    }
}
