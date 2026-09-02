import Testing
@testable import NotchCore

@Suite("Notch reducer: peek and drag")
struct NotchReducerPeekTests {
    private let charging = PeekPayload(id: "charging", duration: .seconds(2))
    private let volume = PeekPayload(id: "volume", duration: .milliseconds(900))

    @Test("a live activity moves a closed notch into peek and arms its timeout")
    func liveActivityPeeks() {
        let transition = NotchReducer.reduce(state: .closed, event: .liveActivity(charging))

        #expect(transition.state.mode == .peek(charging))
        #expect(transition.effects == [.schedulePeekTimeout(.seconds(2))])
    }

    @Test("a second live activity replaces the first and restarts the timeout")
    func liveActivityReplacesPeek() {
        let peeking = NotchState(mode: .peek(charging))
        let transition = NotchReducer.reduce(state: peeking, event: .liveActivity(volume))

        #expect(transition.state.mode == .peek(volume))
        #expect(transition.effects == [.schedulePeekTimeout(.milliseconds(900))])
    }

    @Test("a live activity never interrupts an expanded notch")
    func liveActivityDoesNotInterruptOpen() {
        let open = NotchState(mode: .open, pointerInside: true)
        let transition = NotchReducer.reduce(state: open, event: .liveActivity(charging))

        #expect(transition.state.mode == .open)
        #expect(transition.effects.isEmpty)
    }

    @Test("the peek timeout collapses the notch")
    func peekTimeoutCloses() {
        let peeking = NotchState(mode: .peek(charging))
        let transition = NotchReducer.reduce(state: peeking, event: .peekTimeoutElapsed)

        #expect(transition.state.mode == .closed)
    }

    @Test("a stale peek timeout does not close an expanded notch")
    func stalePeekTimeoutIsIgnored() {
        let open = NotchState(mode: .open, pointerInside: true)
        let transition = NotchReducer.reduce(state: open, event: .peekTimeoutElapsed)

        #expect(transition.state.mode == .open)
    }

    @Test("hovering a peek promotes it to open once the dwell elapses")
    func hoverPromotesPeek() {
        var state = NotchReducer.reduce(state: NotchState(mode: .peek(charging)), event: .pointerEntered).state
        state = NotchReducer.reduce(state: state, event: .hoverDwellElapsed).state

        #expect(state.mode == .open)
    }

    @Test("dragging a file over a closed notch opens it right away")
    func dragOpens() {
        let transition = NotchReducer.reduce(state: .closed, event: .dragEntered)

        #expect(transition.state.mode == .open)
        #expect(transition.effects.contains(.cancelHoverDwell))
    }

    @Test("dragging away with the pointer outside starts the grace period")
    func dragExitStartsGrace() {
        let dragging = NotchState(mode: .open, pointerInside: false)
        let transition = NotchReducer.reduce(state: dragging, event: .dragExited)

        #expect(transition.state.mode == .open)
        #expect(transition.effects == [.scheduleExitGrace])
    }

    @Test("dragging away while the pointer is still inside keeps the notch open")
    func dragExitWithPointerInsideKeepsOpen() {
        let dragging = NotchState(mode: .open, pointerInside: true)
        let transition = NotchReducer.reduce(state: dragging, event: .dragExited)

        #expect(transition.effects.isEmpty)
    }
}
