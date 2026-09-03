import AppKit
import NotchCore
import NotchUI
import Observation
import SwiftUI
import Support

@MainActor
@Observable
public final class TimerModule: NotchModule {
    public static let id = ModuleID("timer")
    public let title = "Timer"
    public let symbolName = "timer"

    /// The cycle. Only this class mutates it, so the tick and the views never
    /// disagree about what "now" was.
    public private(set) var machine: PomodoroMachine

    /// Bumped once a second while the timer runs. Views read it so the countdown
    /// redraws; its value means nothing on its own.
    public private(set) var tick: Int64 = 0

    private let clock = ContinuousClock()
    private var tickTask: Task<Void, Never>?
    private let logger = Log.make("timer")
    /// Held for the life of the module rather than made per completion: an
    /// `NSSound` released while it is still playing cuts itself off.
    private let completionSound = NSSound(named: "Glass")

    public init(configuration: PomodoroConfiguration = PomodoroConfiguration()) {
        machine = PomodoroMachine(configuration: configuration)
    }

    // MARK: NotchModule

    /// Both are deliberately empty, and this module is the one place in the app
    /// where that is correct. Every other module's work is panel-scoped; a
    /// countdown that stopped when the notch closed would not be a timer at all.
    /// The tick therefore belongs to the running machine — `syncTicking()` starts
    /// and stops it — and not to the panel's visibility.
    public func activate() {}
    public func deactivate() {}

    public func expandedView() -> AnyView {
        AnyView(TimerView(module: self))
    }

    public func peekView() -> AnyView? {
        guard hasLiveContent else { return nil }
        // The view reads the module rather than a snapshot, because the registry
        // builds this once per shell redraw and the countdown has to keep moving
        // in between.
        return AnyView(TimerPeekView(module: self))
    }

    /// A timer that has been started still owes the user its countdown, whether
    /// it is running or held mid-phase. Only an untouched one has nothing to say.
    public var hasLiveContent: Bool {
        !machine.isIdle
    }

    // MARK: Controls

    /// The one button the panel needs: start what has not started, hold what is
    /// running, and give back what was held.
    public func toggle() {
        let now = clock.now
        if machine.isRunning {
            machine.pause(at: now)
        } else if machine.isPaused {
            machine.resume(at: now)
        } else {
            machine.start(at: now)
        }
        syncTicking()
    }

    public func skip() {
        machine.skip(at: clock.now)
        syncTicking()
    }

    public func reset() {
        machine.reset()
        syncTicking()
    }

    // MARK: Derived state

    public var remaining: Duration {
        machine.remaining(at: clock.now)
    }

    public var countdownText: String {
        PomodoroClock.text(remaining)
    }

    public var progress: Double {
        machine.progress(at: clock.now)
    }

    // MARK: Ticking

    private func syncTicking() {
        if machine.isRunning {
            startTicking()
        } else {
            tickTask?.cancel()
            tickTask = nil
        }
    }

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.nextTickInterval else { return }
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.advance()
            }
        }
    }

    /// A second, or the rest of the phase when that is shorter — the deadline
    /// rarely falls on a tick boundary, and waiting out the whole second would
    /// leave the phase ending up to a second late and the last second visibly
    /// hanging at 00:01.
    private var nextTickInterval: Duration {
        min(.seconds(1), max(remaining, .milliseconds(20)))
    }

    private func advance() {
        tick &+= 1
        guard let ended = machine.advanceIfElapsed(at: clock.now) else { return }
        logger.info("the \(ended.rawValue, privacy: .public) phase finished")
        announce()
    }

    /// The peek is the notification: the collapsed notch already shows the new
    /// phase, so completion only needs a sound, and deliberately not
    /// `UNUserNotificationCenter` — a timer is not worth a permission prompt.
    private func announce() {
        if completionSound?.play() != true {
            NSSound.beep()
        }
    }
}
