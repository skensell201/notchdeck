import Foundation
import Testing
@testable import NotchCore

/// A scheduler that never touches a real clock: the test decides when timers fire.
final class ManualScheduler: NotchScheduler, @unchecked Sendable {
    final class Handle: NotchCancellable, @unchecked Sendable {
        var isCancelled = false
        func cancel() { isCancelled = true }
    }

    struct Pending {
        let delay: Duration
        let action: () -> Void
        let handle: Handle
    }

    private(set) var pending: [Pending] = []

    func schedule(after delay: Duration, action: @escaping @Sendable () -> Void) -> any NotchCancellable {
        let handle = Handle()
        pending.append(Pending(delay: delay, action: action, handle: handle))
        return handle
    }

    /// Fires every timer that has not been cancelled, in the order it was scheduled.
    func fireAll() {
        let due = pending
        pending = []
        for item in due where !item.handle.isCancelled {
            item.action()
        }
    }

    var lastDelay: Duration? { pending.last?.delay }
}

@MainActor
@Suite("Notch controller")
struct NotchControllerTests {
    private func makeController(
        scheduler: ManualScheduler
    ) -> NotchController {
        NotchController(
            timing: NotchTiming(hoverDwell: .milliseconds(180), exitGrace: .milliseconds(220)),
            scheduler: scheduler
        )
    }

    @Test("hovering schedules the dwell timer with the configured delay")
    func hoverSchedulesDwell() {
        let scheduler = ManualScheduler()
        let controller = makeController(scheduler: scheduler)

        controller.send(.pointerEntered)

        #expect(controller.state.mode == .closed)
        #expect(scheduler.lastDelay == .milliseconds(180))
    }

    @Test("firing the dwell timer opens the notch")
    func dwellOpens() {
        let scheduler = ManualScheduler()
        let controller = makeController(scheduler: scheduler)

        controller.send(.pointerEntered)
        scheduler.fireAll()

        #expect(controller.state.mode == .open)
    }

    @Test("leaving before the dwell fires cancels it, so the notch never opens")
    func leavingCancelsDwell() {
        let scheduler = ManualScheduler()
        let controller = makeController(scheduler: scheduler)

        controller.send(.pointerEntered)
        controller.send(.pointerExited)
        scheduler.fireAll()

        #expect(controller.state.mode == .closed)
    }

    @Test("the grace timer closes an open notch after the pointer leaves")
    func graceCloses() {
        let scheduler = ManualScheduler()
        let controller = makeController(scheduler: scheduler)

        controller.send(.pointerEntered)
        scheduler.fireAll()
        controller.send(.pointerExited)

        #expect(scheduler.lastDelay == .milliseconds(220))

        scheduler.fireAll()

        #expect(controller.state.mode == .closed)
    }

    @Test("a peek uses the payload duration rather than the hover timings")
    func peekUsesPayloadDuration() {
        let scheduler = ManualScheduler()
        let controller = makeController(scheduler: scheduler)

        controller.send(.liveActivity(PeekPayload(id: "volume", duration: .milliseconds(900))))

        #expect(scheduler.lastDelay == .milliseconds(900))
    }

    @Test("observers are notified on every state change")
    func observersAreNotified() {
        let scheduler = ManualScheduler()
        let controller = makeController(scheduler: scheduler)
        var observed: [NotchMode] = []
        controller.onStateChange = { observed.append($0.mode) }

        controller.send(.pointerEntered)
        scheduler.fireAll()
        controller.send(.clicked)

        #expect(observed == [.closed, .open, .pinned])
    }
}
