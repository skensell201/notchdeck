import Foundation
import Testing
@testable import NotchCore

/// Exercises the real `TaskScheduler`, unlike every other test in this target
/// which drives timers through `ManualScheduler`. This is the only place that
/// actually sleeps, so keep delays small.
@MainActor
@Suite("Task scheduler")
struct NotchSchedulerTests {
    /// A plain mutable box. Reads and writes both happen on the main actor
    /// (the closure below is main-actor isolated, and so is this suite), so
    /// there's no data race despite the `@unchecked Sendable`.
    final class Box: @unchecked Sendable {
        var ran = false
    }

    @Test("an uncancelled schedule runs its action")
    func runsWhenNotCancelled() async throws {
        let scheduler = TaskScheduler()
        let box = Box()

        _ = scheduler.schedule(after: .milliseconds(20)) {
            box.ran = true
        }

        try await Task.sleep(for: .milliseconds(80))

        #expect(box.ran == true)
    }

    @Test("cancelling before the deadline suppresses the action")
    func cancelledScheduleNeverRuns() async throws {
        let scheduler = TaskScheduler()
        let box = Box()

        let handle = scheduler.schedule(after: .milliseconds(20)) {
            box.ran = true
        }
        handle.cancel()

        try await Task.sleep(for: .milliseconds(80))

        #expect(box.ran == false)
    }
}
