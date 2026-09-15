public enum ScrollDirection: Equatable, Sendable {
    case up, down, left, right
}

public enum NotchEvent: Equatable, Sendable {
    case pointerEntered
    case pointerExited
    case hoverDwellElapsed
    case exitGraceElapsed
    case scrolled(ScrollDirection)
    case clicked
    case clickedOutside
    case escapePressed
    case dragEntered
    case dragExited
    case liveActivity(PeekPayload)
    case peekTimeoutElapsed
    case dropTimeoutElapsed
}
