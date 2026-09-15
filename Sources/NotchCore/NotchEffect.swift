import Foundation

/// Side effects the reducer asks the controller to perform. The reducer itself
/// never touches a clock, so every transition is testable synchronously.
///
/// The `cancel` cases are idempotent: the reducer sometimes emits one from a
/// mode where the corresponding timer could never have been armed (e.g.
/// `.cancelPeekTimeout` while entering `.open`). Applying a cancel to a timer
/// that was never scheduled, or was already cancelled, is always safe and a
/// no-op.
public enum NotchEffect: Equatable, Sendable {
    case scheduleHoverDwell
    case cancelHoverDwell
    case scheduleExitGrace
    case cancelExitGrace
    case schedulePeekTimeout(Duration)
    case cancelPeekTimeout
    case scheduleDropTimeout(Duration)
}

public struct NotchTransition: Equatable, Sendable {
    public var state: NotchState
    public var effects: [NotchEffect]

    public init(state: NotchState, effects: [NotchEffect] = []) {
        self.state = state
        self.effects = effects
    }
}
