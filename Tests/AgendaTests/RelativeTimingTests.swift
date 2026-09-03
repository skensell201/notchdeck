import Foundation
import Testing
@testable import Agenda

@Suite("Relative timing")
struct RelativeTimingTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func describe(startsIn seconds: TimeInterval, lasting duration: TimeInterval = 1800) -> RelativeTiming {
        let start = Self.now.addingTimeInterval(seconds)
        return RelativeTiming.describe(start: start, end: start.addingTimeInterval(duration), now: Self.now)
    }

    /// Typed rather than inferred: the mixed literal arithmetic below defeats the
    /// type checker inside the macro's argument list.
    private static let countdowns: [(TimeInterval, String)] = [
        (60, "in 1 min"),
        (12 * 60, "in 12 min"),
        (12 * 60 + 59, "in 12 min"),
        (59 * 60, "in 59 min"),
        (60 * 60, "in 1 h"),
        (90 * 60, "in 1 h 30 min"),
        (23 * 3600, "in 23 h"),
        (24 * 3600, "in 1 day"),
        (47 * 3600, "in 1 day"),
        (72 * 3600, "in 3 days")
    ]

    @Test(
        "an upcoming event counts down in the units a person would use",
        arguments: RelativeTimingTests.countdowns
    )
    func countdown(seconds: TimeInterval, expected: String) {
        let timing = describe(startsIn: seconds)

        #expect(timing.text == expected)
        #expect(timing.phase == .upcoming)
    }

    @Test("under a minute says the meeting is starting rather than 'in 0 min'")
    func aboutToStart() {
        #expect(describe(startsIn: 59).text == "starting")
        #expect(describe(startsIn: 1).text == "starting")
    }

    @Test("an event is 'now' from its start until its end")
    func inProgress() {
        #expect(describe(startsIn: 0) == RelativeTiming(phase: .inProgress, text: "now"))
        #expect(describe(startsIn: -1799) == RelativeTiming(phase: .inProgress, text: "now"))
    }

    @Test("an event is over the instant it ends")
    func ended() {
        // The boundary matters: at exactly the end time the meeting is over, and
        // leaving it as "now" keeps a finished meeting highlighted all afternoon.
        #expect(describe(startsIn: -1800) == RelativeTiming(phase: .ended, text: "ended"))
        #expect(describe(startsIn: -7200) == RelativeTiming(phase: .ended, text: "ended"))
    }

    @Test("a zero-length event ends as soon as it starts")
    func instantaneousEvent() {
        #expect(describe(startsIn: 0, lasting: 0).phase == .ended)
        #expect(describe(startsIn: 60, lasting: 0).text == "in 1 min")
    }
}
