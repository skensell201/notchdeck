import Foundation
import NotchUI
import Testing
@testable import Agenda

@Suite("Agenda module")
@MainActor
struct AgendaModuleTests {
    /// A stand-in event store: it answers with whatever the test scripted and
    /// records what it was asked, so the module's window, its permission gating
    /// and its observation lifecycle are all visible without EventKit.
    private final class FakeSource: EventSourcing {
        var authorizationStatus: PermissionStatus
        var statusAfterRequest: PermissionStatus
        /// Named apart from `events(in:)` so the two do not collide.
        var scripted: [AgendaEvent]

        private(set) var requestCount = 0
        private(set) var requestedIntervals: [DateInterval] = []
        private(set) var isObserving = false
        private var onChange: (@MainActor @Sendable () -> Void)?

        init(
            status: PermissionStatus = .granted,
            statusAfterRequest: PermissionStatus = .granted,
            events: [AgendaEvent] = []
        ) {
            self.authorizationStatus = status
            self.statusAfterRequest = statusAfterRequest
            self.scripted = events
        }

        func requestAccess() async -> PermissionStatus {
            requestCount += 1
            authorizationStatus = statusAfterRequest
            return statusAfterRequest
        }

        func events(in interval: DateInterval) -> [AgendaEvent] {
            requestedIntervals.append(interval)
            return scripted.filter { $0.end > interval.start && $0.start < interval.end }
        }

        func startObserving(_ onChange: @escaping @MainActor @Sendable () -> Void) {
            isObserving = true
            self.onChange = onChange
        }

        func stopObserving() {
            isObserving = false
            onChange = nil
        }

        /// Stands in for `EKEventStoreChanged`.
        func announceChange() {
            onChange?()
        }
    }

    // MARK: Fixtures

    private static func calendar() -> Foundation.Calendar {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)!
    }

    private static let now = date("2026-09-03 08:00")

    private static func event(_ title: String, _ start: String, _ end: String) -> AgendaEvent {
        AgendaEvent(id: title, title: title, start: date(start), end: date(end))
    }

    private func module(_ source: FakeSource, daysAhead: Int = 3) -> AgendaModule {
        AgendaModule(
            source: source,
            calendar: Self.calendar(),
            daysAhead: daysAhead,
            now: { Self.now }
        )
    }

    // MARK: Identity

    @Test("the module identifies itself as the calendar")
    func moduleID() {
        #expect(AgendaModule.id.rawValue == "calendar")
    }

    @Test("the calendar never widens the collapsed notch")
    func noPeek() {
        let module = module(FakeSource())

        #expect(module.hasLiveContent == false)
        #expect(module.peekView() == nil)
    }

    // MARK: Activation

    @Test("nothing is fetched until the module is activated")
    func idleUntilActivated() {
        let source = FakeSource(events: [Self.event("Standup", "2026-09-03 09:30", "2026-09-03 09:45")])

        let module = module(source)

        #expect(source.requestedIntervals.isEmpty)
        #expect(module.days.isEmpty)
    }

    @Test("activation fetches and groups")
    func activationFetches() {
        let source = FakeSource(events: [
            Self.event("Standup", "2026-09-03 09:30", "2026-09-03 09:45"),
            Self.event("Retro", "2026-09-04 15:00", "2026-09-04 16:00")
        ])
        let module = module(source)

        module.activate()
        defer { module.deactivate() }

        #expect(module.status == .granted)
        #expect(module.days.map(\.title) == ["Today", "Tomorrow"])
    }

    @Test("the window runs from the start of today to the end of the last day shown")
    func fetchWindow() {
        // From midnight rather than from now: an all-day event and a meeting
        // already in progress both have to be in the answer.
        let source = FakeSource()
        let module = module(source, daysAhead: 3)

        module.activate()
        defer { module.deactivate() }

        #expect(source.requestedIntervals.count == 1)
        #expect(source.requestedIntervals.first?.start == Self.date("2026-09-03 00:00"))
        #expect(source.requestedIntervals.first?.end == Self.date("2026-09-06 00:00"))
    }

    @Test("activation observes the store so a change elsewhere is picked up")
    func activationObserves() {
        let source = FakeSource()
        let module = module(source)

        module.activate()
        defer { module.deactivate() }

        #expect(source.isObserving)
    }

    @Test("a store change refetches")
    func changeRefetches() {
        let source = FakeSource()
        let module = module(source)
        module.activate()
        defer { module.deactivate() }

        source.scripted = [Self.event("Just added", "2026-09-03 11:00", "2026-09-03 11:30")]
        source.announceChange()

        #expect(source.requestedIntervals.count == 2)
        #expect(module.days.first?.timed.map(\.title) == ["Just added"])
    }

    @Test("deactivation stops observing")
    func deactivationStopsObserving() {
        let source = FakeSource()
        let module = module(source)
        module.activate()

        module.deactivate()

        #expect(source.isObserving == false)
        // The last fetch is kept on purpose: a reopened panel would otherwise
        // flash its empty state before the new fetch lands.
        #expect(source.requestedIntervals.count == 1)
    }

    @Test("a change after deactivation is not delivered")
    func silentAfterDeactivation() {
        let source = FakeSource()
        let module = module(source)
        module.activate()
        module.deactivate()

        source.announceChange()

        #expect(source.requestedIntervals.count == 1)
    }

    @Test("reactivating does not stack a second observer")
    func observationIsIdempotent() {
        let source = FakeSource()
        let module = module(source)

        module.activate()
        module.activate()
        defer { module.deactivate() }
        source.announceChange()

        // Two activations, one change: three fetches, not four.
        #expect(source.requestedIntervals.count == 3)
    }

    // MARK: Permission

    @Test("without access nothing is fetched and nothing is observed")
    func noAccessNoFetch() {
        let source = FakeSource(status: .notDetermined, events: [
            Self.event("Standup", "2026-09-03 09:30", "2026-09-03 09:45")
        ])
        let module = module(source)

        module.activate()
        defer { module.deactivate() }

        #expect(module.status == .notDetermined)
        #expect(source.requestedIntervals.isEmpty)
        #expect(source.isObserving == false)
        #expect(module.days.isEmpty)
    }

    @Test("a revoked grant is noticed on the next activation")
    func revokedAccessIsNoticed() {
        // The user can turn the module off in System Settings while the app runs,
        // so the status is re-read every time rather than cached from launch.
        let source = FakeSource(events: [Self.event("Standup", "2026-09-03 09:30", "2026-09-03 09:45")])
        let module = module(source)
        module.activate()
        module.deactivate()

        source.authorizationStatus = .blocked
        module.activate()
        defer { module.deactivate() }

        #expect(module.status == .blocked)
        #expect(source.requestedIntervals.count == 1)
    }

    @Test("granting access fetches straight away, without waiting for a reopen")
    func grantingFetches() async {
        let source = FakeSource(status: .notDetermined, statusAfterRequest: .granted, events: [
            Self.event("Standup", "2026-09-03 09:30", "2026-09-03 09:45")
        ])
        let module = module(source)
        module.activate()
        defer { module.deactivate() }

        await module.requestAccess()

        #expect(source.requestCount == 1)
        #expect(module.status == .granted)
        #expect(module.days.first?.timed.map(\.title) == ["Standup"])
        #expect(source.isObserving)
    }

    @Test("a declined request leaves the module blocked and idle")
    func decliningLeavesItBlocked() async {
        let source = FakeSource(status: .notDetermined, statusAfterRequest: .blocked)
        let module = module(source)
        module.activate()
        defer { module.deactivate() }

        await module.requestAccess()

        #expect(module.status == .blocked)
        #expect(source.requestedIntervals.isEmpty)
        #expect(source.isObserving == false)
    }

    // MARK: Presentation helpers

    @Test("times are formatted in the module's time zone, not the machine's")
    func timeFormatting() {
        let module = module(FakeSource())

        // 09:30 in Berlin, whatever the test machine is set to.
        #expect(module.time(of: Self.date("2026-09-03 09:30")).contains("9:30"))
    }

    @Test("timing is measured against the module's clock")
    func timingUsesTheInjectedClock() {
        let module = module(FakeSource())

        let soon = module.timing(of: Self.event("Standup", "2026-09-03 08:12", "2026-09-03 08:30"))
        let over = module.timing(of: Self.event("Earlier", "2026-09-03 07:00", "2026-09-03 07:30"))

        #expect(soon == RelativeTiming(phase: .upcoming, text: "in 12 min"))
        #expect(over.phase == .ended)
    }
}
