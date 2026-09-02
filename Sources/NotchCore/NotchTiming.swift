import Foundation

public struct NotchTiming: Equatable, Sendable {
    public var hoverDwell: Duration
    public var exitGrace: Duration

    public init(hoverDwell: Duration = .milliseconds(180), exitGrace: Duration = .milliseconds(220)) {
        self.hoverDwell = hoverDwell
        self.exitGrace = exitGrace
    }
}
