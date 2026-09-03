import NotchCore

/// One thing about the machine, watched.
///
/// A source observes exactly one property — the charger, the volume, the output
/// device — and calls back only when there is something worth announcing. The
/// filtering lives in the source, not in whatever consumes it: a peek that
/// arrives is a peek that shows.
@MainActor
public protocol LiveActivitySource: AnyObject {
    /// Begin observing. `emit` is called once per announcement.
    ///
    /// Starting a source that is already started does nothing, so a repeated
    /// `start` cannot end up with two listeners on one property.
    func start(emit: @escaping (PeekPayload) -> Void)
    /// Stop observing and release whatever the system holds on our behalf.
    /// Idempotent, and safe to call without a matching `start`.
    func stop()
}

/// The seam between a source and the machine.
///
/// Split the way the C APIs are: they tell you *that* something changed and
/// leave you to read *what* it now is. Both halves are here, so a test can drive
/// a source through any sequence of readings without a charger or a speaker.
///
/// `read` returns nil when this machine has nothing to say — a Mac mini has no
/// battery, and a device may expose no volume control — and a source that reads
/// nil announces nothing rather than inventing a zero.
@MainActor
public protocol MachineObserving<Reading>: AnyObject {
    associatedtype Reading: Sendable & Equatable

    func read() -> Reading?
    /// Begin delivering change notifications on the main actor.
    ///
    /// The handler is `@Sendable` because it is stored inside a C callback that
    /// the system invokes; it is `@MainActor` because every implementation
    /// registers on the main run loop or the main queue, so the hop is an
    /// assertion rather than a suspension.
    func start(onChange: @escaping @MainActor @Sendable () -> Void)
    func stop()
}
