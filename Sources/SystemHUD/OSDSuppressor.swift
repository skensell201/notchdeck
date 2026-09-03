import Foundation
import Support

/// Control over the system's on-screen-display agent.
public protocol OSDAgentControlling: Sendable {
    func runningAgentPIDs() -> [Int32]
    func suspend(_ pid: Int32)
    func resume(_ pid: Int32)
}

/// Stops macOS drawing its own volume overlay, so ours is not the second one on
/// screen.
///
/// The agent respawns, so suppression is maintained rather than performed once:
/// `enforce()` is called on a timer and catches a new process the moment it
/// appears. Everything suspended is remembered so `restore()` can put it back —
/// leaving the system without its own volume overlay would be a nasty thing to
/// leave behind.
public final class OSDSuppressor: @unchecked Sendable {
    private let control: any OSDAgentControlling
    private let lock = NSLock()
    private var suspendedPIDs: Set<Int32> = []
    private let logger = Log.make("system-hud")

    public init(control: any OSDAgentControlling = LaunchdOSDAgentControl()) {
        self.control = control
    }

    /// Suspends any agent that is running and not already suspended by us.
    public func enforce() {
        let running = control.runningAgentPIDs()
        let newly: [Int32] = lock.withLock {
            let fresh = running.filter { !suspendedPIDs.contains($0) }
            suspendedPIDs.formUnion(fresh)
            return fresh
        }
        for pid in newly {
            control.suspend(pid)
        }
    }

    /// Resumes everything this suppressor suspended. Safe to call twice.
    public func restore() {
        let toResume: Set<Int32> = lock.withLock {
            defer { suspendedPIDs.removeAll() }
            return suspendedPIDs
        }
        for pid in toResume.sorted() {
            control.resume(pid)
        }
    }

    public var isSuppressing: Bool {
        lock.withLock { !suspendedPIDs.isEmpty }
    }
}
