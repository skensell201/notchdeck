import Foundation

/// Side effects the reducer asks the controller to perform. The reducer itself
/// never touches a clock, so every transition is testable synchronously.
public enum NotchEffect: Equatable, Sendable {
    case scheduleHoverDwell
    case cancelHoverDwell
    case scheduleExitGrace
    case cancelExitGrace
    case schedulePeekTimeout(Duration)
    case cancelPeekTimeout
}

public struct NotchTransition: Equatable, Sendable {
    public var state: NotchState
    public var effects: [NotchEffect]

    public init(state: NotchState, effects: [NotchEffect] = []) {
        self.state = state
        self.effects = effects
    }
}
