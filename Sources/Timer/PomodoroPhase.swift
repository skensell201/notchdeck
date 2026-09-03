/// One leg of a pomodoro cycle.
public enum PomodoroPhase: String, Sendable, Equatable, CaseIterable, Codable {
    case work
    case shortBreak
    case longBreak

    /// Shown in the expanded panel. Short, because the panel gives it one line.
    public var title: String {
        switch self {
        case .work: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    /// The glyph the collapsed notch shows beside the countdown. It carries the
    /// whole phase on its own there, so work and rest must not look alike.
    public var symbolName: String {
        switch self {
        case .work: "brain.head.profile"
        case .shortBreak: "cup.and.saucer"
        case .longBreak: "figure.walk"
        }
    }
}

/// How long each phase runs, and how many work phases share a long break.
public struct PomodoroConfiguration: Sendable, Equatable {
    public var work: Duration
    public var shortBreak: Duration
    public var longBreak: Duration
    /// Work phases per cycle; the long break follows the last one. Always at
    /// least 1, because zero work phases would leave the cycle with no way out
    /// of the break.
    public let workPhasesPerCycle: Int

    public init(
        work: Duration = .seconds(25 * 60),
        shortBreak: Duration = .seconds(5 * 60),
        longBreak: Duration = .seconds(15 * 60),
        workPhasesPerCycle: Int = 4
    ) {
        self.work = work
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.workPhasesPerCycle = max(1, workPhasesPerCycle)
    }

    public func duration(of phase: PomodoroPhase) -> Duration {
        switch phase {
        case .work: work
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}
