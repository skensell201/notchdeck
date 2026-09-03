import Foundation

/// How an event sits relative to now: the label, and enough structure for the
/// view to dim what is over without parsing the string back.
public struct RelativeTiming: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case upcoming
        case inProgress
        case ended
    }

    public let phase: Phase
    public let text: String

    public init(phase: Phase, text: String) {
        self.phase = phase
        self.text = text
    }

    /// A pure function of two dates and a third — no clock, no formatter, no
    /// locale — so every boundary is testable and nothing drifts between the
    /// label and the styling that depends on it.
    ///
    /// Deliberately coarse. A countdown to the second would need a timer behind
    /// it, and the number the user acts on is "twelve minutes", not "11:47".
    public static func describe(start: Date, end: Date, now: Date) -> RelativeTiming {
        if now >= end { return RelativeTiming(phase: .ended, text: "ended") }
        if now >= start { return RelativeTiming(phase: .inProgress, text: "now") }

        let seconds = start.timeIntervalSince(now)
        // Under a minute rounds to "in 0 min", which reads as a bug; the event is
        // about to start, so say that.
        if seconds < 60 { return RelativeTiming(phase: .upcoming, text: "starting") }

        let minutes = Int(seconds / 60)
        if minutes < 60 { return RelativeTiming(phase: .upcoming, text: "in \(minutes) min") }

        let hours = minutes / 60
        if hours < 24 {
            let remainder = minutes % 60
            let text = remainder == 0 ? "in \(hours) h" : "in \(hours) h \(remainder) min"
            return RelativeTiming(phase: .upcoming, text: text)
        }

        // Whole days, floored: "in 1 day" covers everything from 24 to 48 hours
        // out, which is as much precision as a date already carries.
        let days = hours / 24
        return RelativeTiming(phase: .upcoming, text: days == 1 ? "in 1 day" : "in \(days) days")
    }
}
