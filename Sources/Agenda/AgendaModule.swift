import Foundation
import NotchCore
import NotchUI
import Observation
import SwiftUI
import Support

/// Today and the next few days, read-only.
@MainActor
@Observable
public final class AgendaModule: NotchModule {
    /// "calendar" rather than "agenda": the identifier is persisted in the user's
    /// layout, and it names the feature, not the target that had to be renamed
    /// to keep `Foundation.Calendar` visible.
    public static let id = ModuleID("calendar")
    public let title = "Calendar"
    public let symbolName = "calendar"

    /// What the module last learned from TCC. Re-read on every activation, since
    /// the user can revoke access in System Settings while the app runs.
    public private(set) var status: PermissionStatus = .notDetermined
    /// The grouped days, newest fetch wins. Empty is a legitimate answer — a
    /// clear week — and the view says so rather than showing a spinner.
    public private(set) var days: [AgendaDay] = []

    let calendar: Foundation.Calendar

    private let source: any EventSourcing
    private let daysAhead: Int
    private let now: () -> Date
    private let timeFormatter: DateFormatter
    private let logger = Log.make("agenda")
    private var isObserving = false

    /// - Parameters:
    ///   - source: the event store seam; the default talks to EventKit.
    ///   - calendar: autoupdating by default so a flight across time zones
    ///     re-groups the days without a relaunch. Tests pass a fixed one.
    ///   - daysAhead: how far the window reaches past the start of today. Three
    ///     is what fits: the panel is 620 points wide and gives each day a column.
    ///   - now: the clock, injected so the window and the countdowns are testable.
    public init(
        source: any EventSourcing = EventKitSource(),
        calendar: Foundation.Calendar = .autoupdatingCurrent,
        daysAhead: Int = 3,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.calendar = calendar
        self.daysAhead = daysAhead
        self.now = now

        // Built once and from the module's calendar, not the machine's: a view
        // that formatted with `.current` would print a different hour than the
        // one the grouping filed the event under.
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        self.timeFormatter = formatter
    }

    // MARK: NotchModule

    public func activate() {
        status = source.authorizationStatus
        guard status == .granted else { return }
        reload()
        startObserving()
    }

    public func deactivate() {
        // A closed notch costs nothing: no observer, and no store notifications
        // rebuilding a list nobody is looking at. The last fetch is kept so a
        // reopened panel is not blank for a frame.
        source.stopObserving()
        isObserving = false
    }

    public func expandedView() -> AnyView {
        guard status == .granted else {
            return AnyView(
                PermissionPrompt(permission: .calendar, status: status) { [weak self] in
                    Task { await self?.requestAccess() }
                }
            )
        }
        return AnyView(AgendaView(module: self))
    }

    /// The calendar never widens the collapsed notch. A meeting starting in five
    /// minutes arguably should, but that is a live-activity decision about what
    /// earns the user's attention, and it belongs with the rest of P3 rather than
    /// being smuggled in here.
    public func peekView() -> AnyView? { nil }
    public var hasLiveContent: Bool { false }

    // MARK: Access

    /// Shows the system prompt and adopts whatever comes back.
    ///
    /// `async` rather than fire-and-forget so tests can await the outcome; the
    /// view wraps it in a `Task` because `PermissionPrompt` hands back a plain
    /// closure.
    public func requestAccess() async {
        status = await source.requestAccess()
        guard status == .granted else {
            logger.notice("calendar access was not granted")
            return
        }
        reload()
        startObserving()
    }

    // MARK: Presentation helpers

    /// The event's time as the user's locale writes it — "09:30", "9:30 AM".
    public func time(of date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Where the event sits relative to the module's clock.
    public func timing(of event: AgendaEvent) -> RelativeTiming {
        RelativeTiming.describe(start: event.start, end: event.end, now: now())
    }

    // MARK: Fetching

    private func reload() {
        let reference = now()
        // From the start of today, not from this instant: an all-day event and a
        // meeting that started before the panel was opened both belong on screen,
        // and so does the morning that has already happened — a calendar that
        // hides what the day contained is harder to read, not easier.
        let start = calendar.startOfDay(for: reference)
        guard let end = calendar.date(byAdding: .day, value: daysAhead, to: start) else {
            logger.error("could not build a \(self.daysAhead, privacy: .public)-day window")
            return
        }
        let events = source.events(in: DateInterval(start: start, end: end))
        days = AgendaGrouping.days(events: events, reference: reference, calendar: calendar)
    }

    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        // Another app adding an event, or a sync landing, must not leave a stale
        // day on screen while the panel is open.
        source.startObserving { [weak self] in
            self?.reload()
        }
    }
}
