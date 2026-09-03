import Foundation
import Testing
@testable import Agenda

@Suite("Agenda grouping")
struct AgendaGroupingTests {
    // MARK: Fixtures

    /// Berlin, because it observes daylight saving and the tests below depend on
    /// a 25-hour day existing. Never `.current`: the answers here are entirely a
    /// function of the time zone and the locale, so reading the machine's would
    /// make the suite pass or fail depending on where it runs.
    private static func calendar(
        timeZone: String = "Europe/Berlin",
        locale: String = "en_US_POSIX"
    ) -> Foundation.Calendar {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    private static func date(
        _ string: String,
        timeZone: String = "Europe/Berlin"
    ) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: timeZone)!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)!
    }

    private static func event(
        _ title: String,
        _ start: String,
        _ end: String,
        allDay: Bool = false
    ) -> AgendaEvent {
        AgendaEvent(
            id: "\(title)-\(start)",
            title: title,
            start: date(start),
            end: date(end),
            isAllDay: allDay
        )
    }

    // MARK: Sections

    @Test("events land in the day they start on, earliest day first")
    func daysAreOrdered() {
        let days = AgendaGrouping.days(
            events: [
                Self.event("Retro", "2026-09-04 15:00", "2026-09-04 16:00"),
                Self.event("Standup", "2026-09-03 09:30", "2026-09-03 09:45")
            ],
            reference: Self.date("2026-09-03 08:00"),
            calendar: Self.calendar()
        )

        #expect(days.map(\.title) == ["Today", "Tomorrow"])
        #expect(days[0].timed.map(\.title) == ["Standup"])
        #expect(days[1].timed.map(\.title) == ["Retro"])
    }

    @Test("a day with nothing in it is not returned at all")
    func emptyDaysAreDropped() {
        // The panel is 150 points tall; a column that says only "Friday" costs as
        // much room as one with two meetings in it.
        let days = AgendaGrouping.days(
            events: [Self.event("Review", "2026-09-05 11:00", "2026-09-05 12:00")],
            reference: Self.date("2026-09-03 08:00"),
            calendar: Self.calendar()
        )

        #expect(days.map(\.title) == ["Saturday"])
    }

    @Test("the third day onwards is named by its weekday")
    func weekdayNames() {
        let days = AgendaGrouping.days(
            events: [
                Self.event("Today", "2026-09-03 10:00", "2026-09-03 11:00"),
                Self.event("Tomorrow", "2026-09-04 10:00", "2026-09-04 11:00"),
                Self.event("Later", "2026-09-06 10:00", "2026-09-06 11:00")
            ],
            reference: Self.date("2026-09-03 08:00"),
            calendar: Self.calendar()
        )

        #expect(days.map(\.title) == ["Today", "Tomorrow", "Sunday"])
    }

    @Test("weekday names follow the calendar's locale, not the machine's")
    func weekdayNamesFollowLocale() {
        let days = AgendaGrouping.days(
            events: [Self.event("Später", "2026-09-06 10:00", "2026-09-06 11:00")],
            reference: Self.date("2026-09-03 08:00"),
            calendar: Self.calendar(locale: "de_DE")
        )

        #expect(days.map(\.title) == ["Sonntag"])
    }

    // MARK: All-day and ordering

    @Test("all-day events are kept apart from timed ones within a day")
    func allDayIsSeparated() {
        let days = AgendaGrouping.days(
            events: [
                Self.event("Standup", "2026-09-03 09:30", "2026-09-03 09:45"),
                Self.event("Public holiday", "2026-09-03 00:00", "2026-09-04 00:00", allDay: true)
            ],
            reference: Self.date("2026-09-03 08:00"),
            calendar: Self.calendar()
        )

        #expect(days.count == 1)
        #expect(days[0].allDay.map(\.title) == ["Public holiday"])
        #expect(days[0].timed.map(\.title) == ["Standup"])
    }

    @Test("all-day events are ordered by name, having no start time to order by")
    func allDayOrderedByTitle() {
        let days = AgendaGrouping.days(
            events: [
                Self.event("Zoe on leave", "2026-09-03 00:00", "2026-09-04 00:00", allDay: true),
                Self.event("Ada on leave", "2026-09-03 00:00", "2026-09-04 00:00", allDay: true)
            ],
            reference: Self.date("2026-09-03 08:00"),
            calendar: Self.calendar()
        )

        #expect(days[0].allDay.map(\.title) == ["Ada on leave", "Zoe on leave"])
    }

    @Test("timed events sort by start, then by the shorter one, then by name")
    func timedOrdering() {
        let days = AgendaGrouping.days(
            events: [
                Self.event("Long", "2026-09-03 10:00", "2026-09-03 12:00"),
                Self.event("Zebra", "2026-09-03 10:00", "2026-09-03 10:30"),
                Self.event("Alpha", "2026-09-03 10:00", "2026-09-03 10:30"),
                Self.event("Early", "2026-09-03 09:00", "2026-09-03 09:15")
            ],
            reference: Self.date("2026-09-03 08:00"),
            calendar: Self.calendar()
        )

        // A stable order matters beyond looking tidy: the list is rebuilt on every
        // store change, and an unstable sort would reshuffle rows under the cursor.
        #expect(days[0].timed.map(\.title) == ["Early", "Alpha", "Zebra", "Long"])
    }

    // MARK: In progress and multi-day

    @Test("an event already running is filed under today, not under the day it began")
    func runningEventMovesToToday() {
        let days = AgendaGrouping.days(
            events: [
                Self.event("Conference", "2026-09-01 09:00", "2026-09-05 18:00")
            ],
            reference: Self.date("2026-09-03 08:00"),
            calendar: Self.calendar()
        )

        #expect(days.map(\.title) == ["Today"])
        #expect(days[0].date == Self.date("2026-09-03 00:00"))
    }

    @Test("an event that has already ended stays on the day it happened")
    func finishedEventStaysPut() {
        // The opposite of the rule above, and the reason it is conditional: an
        // event that finished yesterday must not be dragged forward into today.
        let days = AgendaGrouping.days(
            events: [Self.event("Yesterday's talk", "2026-09-02 09:00", "2026-09-02 10:00")],
            reference: Self.date("2026-09-03 08:00"),
            calendar: Self.calendar()
        )

        #expect(days[0].date == Self.date("2026-09-02 00:00"))
    }

    // MARK: Boundaries

    @Test("a month boundary is just the next day")
    func monthBoundary() {
        let days = AgendaGrouping.days(
            events: [
                Self.event("New month", "2026-10-01 09:00", "2026-10-01 10:00"),
                Self.event("Month end", "2026-09-30 17:00", "2026-09-30 18:00")
            ],
            reference: Self.date("2026-09-30 08:00"),
            calendar: Self.calendar()
        )

        #expect(days.map(\.title) == ["Today", "Tomorrow"])
        #expect(days[1].date == Self.date("2026-10-01 00:00"))
    }

    @Test("a year boundary is just the next day too")
    func yearBoundary() {
        let days = AgendaGrouping.days(
            events: [
                Self.event("Fireworks", "2027-01-01 00:30", "2027-01-01 01:00"),
                Self.event("Last standup", "2026-12-31 09:30", "2026-12-31 09:45")
            ],
            reference: Self.date("2026-12-31 08:00"),
            calendar: Self.calendar()
        )

        #expect(days.map(\.title) == ["Today", "Tomorrow"])
    }

    @Test("the 25-hour day when daylight saving ends is still one day")
    func daylightSavingEnds() {
        // Berlin turns the clocks back at 03:00 on 2026-10-25, so that day has 25
        // hours. Two events either side of the change belong to the same section,
        // and a naive "start of day plus 86 400 seconds" would split them.
        let days = AgendaGrouping.days(
            events: [
                Self.event("Before the change", "2026-10-25 01:30", "2026-10-25 02:00"),
                Self.event("After the change", "2026-10-25 04:00", "2026-10-25 05:00")
            ],
            reference: Self.date("2026-10-25 00:30"),
            calendar: Self.calendar()
        )

        #expect(days.count == 1)
        #expect(days[0].title == "Today")
        #expect(days[0].timed.count == 2)
    }

    @Test("the day after the clocks change is Tomorrow, not still today")
    func tomorrowAcrossDaylightSaving() {
        // The arithmetic that gets this wrong adds 24 hours to midnight, which on
        // a 25-hour day lands at 23:00 the same evening.
        let days = AgendaGrouping.days(
            events: [Self.event("Monday standup", "2026-10-26 09:30", "2026-10-26 09:45")],
            reference: Self.date("2026-10-25 10:00"),
            calendar: Self.calendar()
        )

        #expect(days.map(\.title) == ["Tomorrow"])
    }

    @Test("the 23-hour day when daylight saving starts is still one day")
    func daylightSavingStarts() {
        // 2026-03-29: 02:00 becomes 03:00 in Berlin, so the day is 23 hours long.
        let days = AgendaGrouping.days(
            events: [
                Self.event("Early", "2026-03-29 01:00", "2026-03-29 01:30"),
                Self.event("Late", "2026-03-29 23:00", "2026-03-29 23:30")
            ],
            reference: Self.date("2026-03-29 00:30"),
            calendar: Self.calendar()
        )

        #expect(days.count == 1)
        #expect(days[0].timed.count == 2)
    }

    @Test("the same instants group differently in a different time zone")
    func timeZoneDecidesTheDay() {
        // 23:30 in Berlin is 22:30 UTC — the same day. 00:30 Berlin is 23:30 UTC
        // the day before, which is the whole reason the calendar is a parameter.
        let lateEvent = AgendaEvent(
            id: "late",
            title: "Late call",
            start: Self.date("2026-09-04 00:30"),
            end: Self.date("2026-09-04 01:00")
        )
        let reference = Self.date("2026-09-03 20:00")

        let berlin = AgendaGrouping.days(events: [lateEvent], reference: reference, calendar: Self.calendar())
        let utc = AgendaGrouping.days(
            events: [lateEvent],
            reference: reference,
            calendar: Self.calendar(timeZone: "UTC")
        )

        #expect(berlin.map(\.title) == ["Tomorrow"])
        #expect(utc.map(\.title) == ["Today"])
    }

    @Test("no events means no days")
    func emptyInput() {
        #expect(
            AgendaGrouping.days(
                events: [],
                reference: Self.date("2026-09-03 08:00"),
                calendar: Self.calendar()
            ).isEmpty
        )
    }
}
