public enum ScrollPhase: Equatable, Sendable {
    case began, changed, ended
}

public enum ScrollGesture: Equatable, Sendable {
    case open
    case close
    case nextTrack
    case previousTrack
}

/// Turns a stream of raw scroll deltas into at most one gesture per swipe.
public struct ScrollAccumulator: Sendable {
    public struct Thresholds: Sendable {
        public var vertical: Double
        public var horizontal: Double

        public init(vertical: Double = 30, horizontal: Double = 45) {
            self.vertical = vertical
            self.horizontal = horizontal
        }
    }

    private let thresholds: Thresholds
    private var totalX: Double = 0
    private var totalY: Double = 0
    private var fired = false

    public init(thresholds: Thresholds = .init()) {
        self.thresholds = thresholds
    }

    public mutating func consume(deltaX: Double, deltaY: Double, phase: ScrollPhase) -> ScrollGesture? {
        switch phase {
        case .began:
            reset()
        case .ended:
            reset()
            return nil
        case .changed:
            break
        }

        guard !fired else { return nil }

        totalX += deltaX
        totalY += deltaY

        let verticalReady = abs(totalY) >= thresholds.vertical
        let horizontalReady = abs(totalX) >= thresholds.horizontal

        if verticalReady, abs(totalY) >= abs(totalX) {
            fired = true
            return totalY > 0 ? .open : .close
        }

        if horizontalReady {
            fired = true
            return totalX > 0 ? .previousTrack : .nextTrack
        }

        return nil
    }

    private mutating func reset() {
        totalX = 0
        totalY = 0
        fired = false
    }
}
