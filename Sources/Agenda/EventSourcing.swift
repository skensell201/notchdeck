import Foundation
import NotchUI

/// The seam between the module and EventKit.
///
/// Everything EventKit-shaped stops here: the module deals in `AgendaEvent` and
/// `PermissionStatus`, so it can be driven from a fake with no event store, no
/// TCC prompt, and no dependence on what happens to be in the user's calendar.
@MainActor
public protocol EventSourcing: AnyObject {
    /// What TCC currently says. Cheap; safe to read on every activation.
    var authorizationStatus: PermissionStatus { get }

    /// Shows the system prompt if the user has never been asked, and answers with
    /// the status afterwards. Asking again once blocked does nothing, which is
    /// why `PermissionPrompt` sends those users to System Settings instead.
    func requestAccess() async -> PermissionStatus

    /// Events overlapping `interval`, in no particular order.
    func events(in interval: DateInterval) -> [AgendaEvent]

    /// Calls `onChange` whenever the underlying store changes — another app
    /// adding an event, a sync landing — so the panel does not show a stale day.
    /// Idempotent: a second call replaces the first observer.
    func startObserving(_ onChange: @escaping @MainActor @Sendable () -> Void)
    func stopObserving()
}
