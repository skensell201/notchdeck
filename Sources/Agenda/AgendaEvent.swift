import Foundation

/// A calendar event, flattened to plain values.
///
/// Deliberately not an `EKEvent`: everything downstream — grouping, the meeting
/// link detector, the view — is then testable from literals, and the only code
/// that needs a real event store is `EventKitSource`.
public struct AgendaEvent: Identifiable, Hashable, Sendable {
    /// EventKit's `eventIdentifier`, or any stable string. A recurring event
    /// shares one identifier across occurrences, so the start is folded in by
    /// `EventKitSource` to keep two occurrences distinct in a `ForEach`.
    public let id: String
    public let title: String
    public let start: Date
    /// For an all-day event this is the exclusive end EventKit reports, which is
    /// midnight at the start of the following day.
    public let end: Date
    public let isAllDay: Bool
    /// The owning calendar's colour, so several calendars are told apart at a
    /// glance. Nil when the calendar has none.
    public let calendarColor: EventColor?
    public let location: String?
    public let notes: String?
    public let url: URL?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarColor: EventColor? = nil,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarColor = calendarColor
        self.location = location
        self.notes = notes
        self.url = url
    }
}

/// A calendar's colour as plain components.
///
/// `CGColor` would work but is neither `Hashable` nor comfortable in a test
/// literal, and the view needs nothing more than these three numbers.
public struct EventColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}
