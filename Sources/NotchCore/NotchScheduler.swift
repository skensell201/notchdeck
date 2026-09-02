import Foundation

public protocol NotchCancellable: Sendable {
    func cancel()
}

/// Injected so tests can drive timers without waiting on a real clock.
public protocol NotchScheduler: Sendable {
    /// Schedules `action` to run on the main actor after `delay`.
    ///
    /// Implementations must deliver on the main actor, and must not invoke
    /// `action` before `schedule` returns — the controller records the returned
    /// handle only once this call completes, and a synchronous delivery would
    /// re-enter `send` while the effect list is still being applied.
    func schedule(after delay: Duration, action: @escaping @MainActor @Sendable () -> Void) -> any NotchCancellable
}

public struct TaskScheduler: NotchScheduler {
    public init() {}

    public func schedule(after delay: Duration, action: @escaping @MainActor @Sendable () -> Void) -> any NotchCancellable {
        let task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskCancellable(task: task)
    }

    private struct TaskCancellable: NotchCancellable {
        let task: Task<Void, Never>
        func cancel() { task.cancel() }
    }
}
