import Foundation

/// One day's worth of events, ready to render.
public struct AgendaDay: Identifiable, Hashable, Sendable {
    /// Midnight at the start of the day, in the grouping calendar's time zone.
    public let date: Date
    /// "Today", "Tomorrow", or the weekday name.
    public let title: String
    /// All-day events, first because they frame the day rather than sit in it.
    public let allDay: [AgendaEvent]
    /// Timed events, earliest first.
    public let timed: [AgendaEvent]

    public var id: Date { date }

    public init(date: Date, title: String, allDay: [AgendaEvent], timed: [AgendaEvent]) {
        self.date = date
        self.title = title
        self.allDay = allDay
        self.timed = timed
    }
}

/// Turns a flat list of events into day sections.
///
/// Every entry point takes its `Foundation.Calendar` explicitly — never
/// `.current` — because the answer depends entirely on the time zone and the
/// locale, and a function that reads the machine's cannot be tested. It is also
/// why this target is called `Agenda`: a target named `Calendar` would shadow
/// `Foundation.Calendar` in every file that imported it.
public enum AgendaGrouping {
    /// Days with at least one event, earliest first.
    ///
    /// Days with nothing in them are dropped rather than returned empty: the
    /// panel is 150 points tall, and a column reading "Thursday — nothing" costs
    /// as much room as one with two meetings in it.
    public static func days(
        events: [AgendaEvent],
        reference: Date,
        calendar: Foundation.Calendar
    ) -> [AgendaDay] {
        var buckets: [Date: [AgendaEvent]] = [:]
        for event in events {
            buckets[day(of: event, reference: reference, calendar: calendar), default: []].append(event)
        }

        return buckets.keys.sorted().map { date in
            let events = buckets[date] ?? []
            return AgendaDay(
                date: date,
                title: title(for: date, reference: reference, calendar: calendar),
                // All-day events have no start time to sort by — every one of them
                // begins at midnight — so they are ordered by name instead.
                allDay: events.filter(\.isAllDay).sorted { $0.title < $1.title },
                timed: events.filter { !$0.isAllDay }.sorted(by: earlierFirst)
            )
        }
    }

    /// The day an event belongs under.
    ///
    /// Normally the day it starts on. The exception is an event already in
    /// progress at `reference` — a three-day conference, a meeting that started
    /// before the panel was opened — which belongs under today, where the user is
    /// looking, rather than under the day it began.
    static func day(of event: AgendaEvent, reference: Date, calendar: Foundation.Calendar) -> Date {
        let startOfEvent = calendar.startOfDay(for: event.start)
        let today = calendar.startOfDay(for: reference)
        guard event.start <= reference, reference < event.end else { return startOfEvent }
        return max(startOfEvent, today)
    }

    static func title(for day: Date, reference: Date, calendar: Foundation.Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: reference) { return "Today" }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference))
        if let tomorrow, calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        // `weekdaySymbols` follows the calendar's locale, so a calendar built for
        // a test locale gives the same answer on every machine. It is indexed
        // from Sunday, which is what `.weekday` counts from too — `firstWeekday`
        // decides where a week *starts*, not how weekdays are numbered.
        let symbols = calendar.weekdaySymbols
        let index = calendar.component(.weekday, from: day) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    /// Earliest start wins; ties go to the shorter event, then to the title, so
    /// two meetings at 10:00 keep a stable order between refreshes.
    private static func earlierFirst(_ lhs: AgendaEvent, _ rhs: AgendaEvent) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        return lhs.title < rhs.title
    }
}
