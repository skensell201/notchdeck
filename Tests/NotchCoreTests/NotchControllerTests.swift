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
        let action: @MainActor @Sendable () -> Void
        let handle: Handle
    }

    private(set) var pending: [Pending] = []

    func schedule(after delay: Duration, action: @escaping @MainActor @Sendable () -> Void) -> any NotchCancellable {
        let handle = Handle()
        pending.append(Pending(delay: delay, action: action, handle: handle))
        return handle
    }

    /// Fires every timer that has not been cancelled, in deadline order (soonest first),
    /// matching how real timers fire. Note this is only true deadline order for timers
    /// armed in the same pass: each delay is relative to when its own timer was armed,
    /// not to a shared clock, so timers armed across separate passes aren't comparable
    /// this way.
    @MainActor
    func fireAll() {
        let due = pending.sorted { $0.delay < $1.delay }
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
        let payload = PeekPayload(id: "volume", duration: .milliseconds(900))

        controller.send(.liveActivity(payload))

        #expect(scheduler.lastDelay == .milliseconds(900))
        #expect(controller.state.mode == .peek(payload))
    }

    @Test("observers are notified on state changes, not on ignored events")
    func observersAreNotified() {
        let scheduler = ManualScheduler()
        let controller = makeController(scheduler: scheduler)
        var observed: [NotchMode] = []
        controller.onStateChange = { observed.append($0.mode) }

        // Ignored from `.closed`: the reducer leaves state untouched, so no notification.
        controller.send(.scrolled(.left))
        #expect(observed.isEmpty)

        controller.send(.pointerEntered)
        scheduler.fireAll()
        controller.send(.clicked)

        #expect(observed == [.closed, .open, .pinned])
    }

    @Test("re-entering while the dwell timer is pending cancels the earlier timer")
    func rearmCancelsPreviousDwell() {
        let scheduler = ManualScheduler()
        let controller = makeController(scheduler: scheduler)

        controller.send(.pointerEntered)
        controller.send(.pointerEntered)

        #expect(scheduler.pending.count == 2)
        let liveCount = scheduler.pending.filter { !$0.handle.isCancelled }.count
        #expect(liveCount == 1)

        scheduler.fireAll()

        #expect(controller.state.mode == .open)
    }

    @Test("cancelling a timer that was never armed is a harmless no-op")
    func cancelIdempotency() {
        let scheduler = ManualScheduler()
        let controller = makeController(scheduler: scheduler)

        // `.pointerExited` from `.closed` emits `.cancelHoverDwell`, but no dwell
        // timer has ever been armed here — the cancel must be a no-op.
        controller.send(.pointerExited)

        #expect(controller.state.mode == .closed)
        #expect(controller.state.pointerInside == false)
        #expect(scheduler.pending.isEmpty)
    }
}
