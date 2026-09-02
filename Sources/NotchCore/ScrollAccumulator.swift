import Foundation

public enum ScrollPhase: Equatable, Sendable {
    /// A trackpad gesture began: fingers went down.
    case began
    /// A delta inside an ongoing trackpad gesture.
    case changed
    /// A trackpad gesture ended: fingers lifted.
    case ended
    /// An inertial delta synthesised after the fingers lifted. Ignored outright —
    /// it belongs to the flick that has already had its say.
    case momentum
    /// A delta from a device with no gesture phases at all, such as a conventional
    /// mouse wheel. Bounded by the idle interval rather than by a phase.
    case discrete
}

/// Turns a stream of raw scroll deltas into at most one direction per swipe.
///
/// This is a value type whose whole purpose is the `fired` latch. Store it as a
/// `var` stored property and mutate it in place: copying it into a closure or
/// passing it by value duplicates the latch, and the copy will happily report the
/// gesture the original just suppressed.
public struct ScrollAccumulator: Sendable {
    public struct Configuration: Sendable {
        public var vertical: Double
        public var horizontal: Double
        /// A gap this long between deltas ends the gesture for devices that never
        /// send `.ended`, so a wheel keeps working after its first swipe.
        public var idleInterval: TimeInterval

        public init(vertical: Double = 30, horizontal: Double = 45, idleInterval: TimeInterval = 0.15) {
            self.vertical = vertical
            self.horizontal = horizontal
            self.idleInterval = idleInterval
        }
    }

    private let configuration: Configuration
    private var totalX: Double = 0
    private var totalY: Double = 0
    private var fired = false
    private var lastTimestamp: TimeInterval?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func consume(
        deltaX: Double,
        deltaY: Double,
        phase: ScrollPhase,
        timestamp: TimeInterval
    ) -> ScrollDirection? {
        // Inertia belongs to the flick that already had its say: change nothing.
        guard phase != .momentum else { return nil }

        if let lastTimestamp, timestamp - lastTimestamp > configuration.idleInterval {
            reset()
        }

        switch phase {
        case .began:
            reset()
        case .ended:
            reset()
            return nil
        case .changed, .discrete:
            break
        case .momentum:
            return nil
        }

        lastTimestamp = timestamp

        guard !fired else { return nil }

        totalX += deltaX
        totalY += deltaY

        if abs(totalY) >= configuration.vertical, abs(totalY) >= abs(totalX) {
            fired = true
            return totalY > 0 ? .down : .up
        }

        if abs(totalX) >= configuration.horizontal, abs(totalX) >= abs(totalY) {
            fired = true
            return totalX > 0 ? .right : .left
        }

        return nil
    }

    private mutating func reset() {
        totalX = 0
        totalY = 0
        fired = false
    }
}
