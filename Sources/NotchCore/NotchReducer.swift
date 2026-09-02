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
            case .closed:
                return NotchTransition(state: state, effects: [.cancelHoverDwell])
            case .peek(let payload):
                return NotchTransition(state: state, effects: [.cancelHoverDwell, .schedulePeekTimeout(payload.duration)])
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

        case .scrolled(let direction):
            switch state.mode {
            case .closed, .peek:
                guard direction == .down else { return NotchTransition(state: state) }
                state.mode = .open
                return NotchTransition(state: state, effects: [.cancelHoverDwell, .cancelPeekTimeout])
            case .open:
                guard direction == .up else { return NotchTransition(state: state) }
                state.mode = .closed
                return NotchTransition(state: state, effects: [.cancelExitGrace])
            case .pinned:
                return NotchTransition(state: state)
            }

        case .clicked:
            switch state.mode {
            case .closed, .peek:
                state.mode = .open
                return NotchTransition(state: state, effects: [.cancelHoverDwell, .cancelPeekTimeout])
            case .open:
                state.mode = .pinned
                return NotchTransition(state: state, effects: [.cancelExitGrace])
            case .pinned:
                return NotchTransition(state: state)
            }

        case .clickedOutside, .escapePressed:
            // Deliberately leaves `pointerInside` untouched: dismissing while the
            // pointer is still over the notch must not spring it back open. It
            // stays closed until the pointer leaves and re-enters.
            switch state.mode {
            case .open, .pinned:
                state.mode = .closed
                return NotchTransition(state: state, effects: [.cancelExitGrace, .cancelHoverDwell])
            case .closed, .peek:
                return NotchTransition(state: state)
            }

        case .dragEntered:
            switch state.mode {
            case .closed, .peek:
                state.mode = .open
                return NotchTransition(state: state, effects: [.cancelHoverDwell, .cancelPeekTimeout])
            case .open, .pinned:
                return NotchTransition(state: state, effects: [.cancelExitGrace])
            }

        case .dragExited:
            guard case .open = state.mode, !state.pointerInside else {
                return NotchTransition(state: state)
            }
            return NotchTransition(state: state, effects: [.scheduleExitGrace])

        case .liveActivity(let payload):
            switch state.mode {
            case .closed, .peek:
                state.mode = .peek(payload)
                return NotchTransition(state: state, effects: [.schedulePeekTimeout(payload.duration)])
            case .open, .pinned:
                return NotchTransition(state: state)
            }

        case .peekTimeoutElapsed:
            guard case .peek = state.mode else { return NotchTransition(state: state) }
            state.mode = .closed
            return NotchTransition(state: state)
        }
    }
}
