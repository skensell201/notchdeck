import Foundation

/// Owns the notch state and turns reducer effects into real timers.
@MainActor
public final class NotchController {
    public private(set) var state = NotchState()
    public var onStateChange: ((NotchState) -> Void)?

    /// Settable so the settings window's sliders take effect at once rather than
    /// at the next launch. A timer already armed keeps its original delay; the
    /// next one uses the new value, which is what the user is about to test.
    public var timing: NotchTiming
    private let scheduler: any NotchScheduler

    private var hoverDwell: (any NotchCancellable)?
    private var exitGrace: (any NotchCancellable)?
    private var peekTimeout: (any NotchCancellable)?

    public init(timing: NotchTiming = NotchTiming(), scheduler: any NotchScheduler = TaskScheduler()) {
        self.timing = timing
        self.scheduler = scheduler
    }

    deinit {
        hoverDwell?.cancel()
        exitGrace?.cancel()
        peekTimeout?.cancel()
    }

    public func send(_ event: NotchEvent) {
        let transition = NotchReducer.reduce(state: state, event: event)
        let didChange = transition.state != state
        state = transition.state
        for effect in transition.effects {
            apply(effect)
        }
        // Pass `state` (the property), not `transition.state`: if an observer
        // re-enters with `send`, `state` will already reflect that later
        // transition by the time this callback runs, so the observer always
        // sees the latest value rather than a stale snapshot captured here.
        if didChange {
            onStateChange?(state)
        }
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
            self?.send(event)
        }
    }
}
