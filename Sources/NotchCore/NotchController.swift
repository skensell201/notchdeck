import Foundation

/// Owns the notch state and turns reducer effects into real timers.
@MainActor
public final class NotchController {
    public private(set) var state = NotchState()
    public var onStateChange: ((NotchState) -> Void)?

    private let timing: NotchTiming
    private let scheduler: any NotchScheduler

    private var hoverDwell: (any NotchCancellable)?
    private var exitGrace: (any NotchCancellable)?
    private var peekTimeout: (any NotchCancellable)?

    public init(timing: NotchTiming = NotchTiming(), scheduler: any NotchScheduler = TaskScheduler()) {
        self.timing = timing
        self.scheduler = scheduler
    }

    public func send(_ event: NotchEvent) {
        let transition = NotchReducer.reduce(state: state, event: event)
        state = transition.state
        for effect in transition.effects {
            apply(effect)
        }
        onStateChange?(state)
    }

    private func apply(_ effect: NotchEffect) {
        switch effect {
        case .scheduleHoverDwell:
            hoverDwell?.cancel()
            hoverDwell = schedule(after: timing.hoverDwell, event: .hoverDwellElapsed)
        case .cancelHoverDwell:
            hoverDwell?.cancel()
            hoverDwell = nil
        case .scheduleExitGrace:
            exitGrace?.cancel()
            exitGrace = schedule(after: timing.exitGrace, event: .exitGraceElapsed)
        case .cancelExitGrace:
            exitGrace?.cancel()
            exitGrace = nil
        case .schedulePeekTimeout(let duration):
            peekTimeout?.cancel()
            peekTimeout = schedule(after: duration, event: .peekTimeoutElapsed)
        case .cancelPeekTimeout:
            peekTimeout?.cancel()
            peekTimeout = nil
        }
    }

    private func schedule(after delay: Duration, event: NotchEvent) -> any NotchCancellable {
        scheduler.schedule(after: delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.send(event)
            }
        }
    }
}
