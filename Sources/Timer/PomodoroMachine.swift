/// The pomodoro cycle as a value: work, a break, work again, and a long break
/// after the last work phase of the cycle.
///
/// There is no clock inside. Every operation that needs to know the time is
/// handed it, which is what makes the whole machine testable to the second
/// without waiting for one, and what lets the module drive it from a single
/// `ContinuousClock` it owns.
public struct PomodoroMachine: Sendable, Equatable {
    public typealias Instant = ContinuousClock.Instant

    /// What the current phase is doing.
    ///
    /// The associated values are the point: only a running phase has a deadline,
    /// only a held one carries time left, and an idle phase carries neither
    /// because it has not started. A paused machine therefore cannot be asked
    /// for a deadline that would silently keep counting down, and an idle one
    /// cannot claim elapsed time it never spent.
    public enum Activity: Sendable, Equatable {
        case idle
        case running(until: Instant)
        case paused(remaining: Duration)
    }

    public let configuration: PomodoroConfiguration
    public private(set) var phase: PomodoroPhase
    public private(set) var activity: Activity
    /// Work phases finished so far in this cycle, `0...workPhasesPerCycle`. It
    /// reaches the cycle length during the long break and falls back to zero when
    /// that break ends.
    public private(set) var completedWorkPhases: Int

    public init(configuration: PomodoroConfiguration = PomodoroConfiguration()) {
        self.configuration = configuration
        self.phase = .work
        self.activity = .idle
        self.completedWorkPhases = 0
    }

    // MARK: Reading

    public var isIdle: Bool {
        if case .idle = activity { return true }
        return false
    }

    public var isRunning: Bool {
        if case .running = activity { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = activity { return true }
        return false
    }

    /// Which work phase of the cycle is current, 1-based, for "Focus 2 of 4".
    /// During a break it is the work phase that just ended.
    public var workPhaseNumber: Int {
        switch phase {
        case .work: min(completedWorkPhases + 1, configuration.workPhasesPerCycle)
        case .shortBreak, .longBreak: max(completedWorkPhases, 1)
        }
    }

    /// Time left in the current phase, never negative: a deadline that has passed
    /// reads as zero rather than counting up in the other direction.
    public func remaining(at now: Instant) -> Duration {
        switch activity {
        case .idle:
            // Nothing has been spent yet, so the whole phase is left.
            configuration.duration(of: phase)
        case .paused(let remaining):
            remaining
        case .running(let deadline):
            max(.zero, deadline - now)
        }
    }

    /// How much of the current phase is spent, `0...1`, for the progress ring.
    public func progress(at now: Instant) -> Double {
        let total = configuration.duration(of: phase).inSeconds
        guard total > 0 else { return 1 }
        return min(max(1 - remaining(at: now).inSeconds / total, 0), 1)
    }

    // MARK: Transitions

    /// Starts the current phase. Only an idle phase can start; a running one is
    /// already started, and a paused one is resumed rather than restarted, which
    /// would throw away the time it had already spent.
    public mutating func start(at now: Instant) {
        guard isIdle else { return }
        activity = .running(until: now + configuration.duration(of: phase))
    }

    /// Holds the phase at whatever is left of it. The deadline is dropped, so no
    /// amount of paused time can eat into the phase.
    public mutating func pause(at now: Instant) {
        guard isRunning else { return }
        activity = .paused(remaining: remaining(at: now))
    }

    /// Gives back exactly what pausing held, measured forward from now.
    public mutating func resume(at now: Instant) {
        guard case .paused(let remaining) = activity else { return }
        activity = .running(until: now + remaining)
    }

    /// Ends the current phase early and moves to the next one, counting a skipped
    /// work phase towards the long break — skipping is the user saying they are
    /// done with it, not that it never happened.
    ///
    /// A running machine keeps running into the next phase; an idle or paused one
    /// lands on the next phase idle, so skipping never starts a timer the user
    /// had deliberately stopped.
    public mutating func skip(at now: Instant) {
        advance(at: now, autostart: isRunning)
    }

    /// Returns to the start of the cycle: the first work phase, not yet started.
    public mutating func reset() {
        phase = .work
        activity = .idle
        completedWorkPhases = 0
    }

    /// Advances if the running phase's deadline has passed, and returns the phase
    /// that ended so the caller can announce it. Returns nil otherwise.
    ///
    /// Exactly one phase advances per call, and the next one is measured from
    /// `now` rather than from the deadline that passed. After the lid has been
    /// shut for an hour the user gets one completion and a full fresh phase,
    /// instead of the machine silently racing through the phases it slept past.
    @discardableResult
    public mutating func advanceIfElapsed(at now: Instant) -> PomodoroPhase? {
        guard case .running(let deadline) = activity, now >= deadline else { return nil }
        let ended = phase
        advance(at: now, autostart: true)
        return ended
    }

    private mutating func advance(at now: Instant, autostart: Bool) {
        switch phase {
        case .work:
            completedWorkPhases += 1
            phase = completedWorkPhases >= configuration.workPhasesPerCycle ? .longBreak : .shortBreak
        case .shortBreak:
            phase = .work
        case .longBreak:
            // The long break closes the cycle, so the count starts over with it.
            completedWorkPhases = 0
            phase = .work
        }
        activity = autostart ? .running(until: now + configuration.duration(of: phase)) : .idle
    }
}

extension Duration {
    /// Seconds as a double, for the ratios the progress ring needs. Lossy by
    /// definition, and never used for the countdown itself.
    var inSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
