public enum NotchReducer {
    public static func reduce(state: NotchState, event: NotchEvent) -> NotchTransition {
        var state = state

        switch event {
        case .pointerEntered:
            state.pointerInside = true
            switch state.mode {
            case .closed:
                return NotchTransition(state: state, effects: [.scheduleHoverDwell])
            case .peek:
                return NotchTransition(state: state, effects: [.scheduleHoverDwell, .cancelPeekTimeout])
            case .open, .pinned:
                return NotchTransition(state: state, effects: [.cancelExitGrace])
            }

        case .pointerExited:
            state.pointerInside = false
            switch state.mode {
            case .closed, .peek:
                return NotchTransition(state: state, effects: [.cancelHoverDwell])
            case .open:
                return NotchTransition(state: state, effects: [.scheduleExitGrace])
            case .pinned:
                return NotchTransition(state: state)
            }

        case .hoverDwellElapsed:
            guard state.pointerInside else { return NotchTransition(state: state) }
            switch state.mode {
            case .closed, .peek:
                state.mode = .open
                return NotchTransition(state: state, effects: [.cancelPeekTimeout, .cancelExitGrace])
            case .open, .pinned:
                return NotchTransition(state: state)
            }

        case .exitGraceElapsed:
            guard case .open = state.mode, !state.pointerInside else {
                return NotchTransition(state: state)
            }
            state.mode = .closed
            return NotchTransition(state: state)

        default:
            return NotchTransition(state: state)
        }
    }
}
