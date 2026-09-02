import Foundation

public protocol NotchCancellable: Sendable {
    func cancel()
}

/// Injected so tests can drive timers without waiting on a real clock.
public protocol NotchScheduler: Sendable {
    func schedule(after delay: Duration, action: @escaping @Sendable () -> Void) -> any NotchCancellable
}

public struct TaskScheduler: NotchScheduler {
    public init() {}

    public func schedule(after delay: Duration, action: @escaping @Sendable () -> Void) -> any NotchCancellable {
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
