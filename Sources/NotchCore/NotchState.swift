import Foundation

/// A transient notification shown beside the collapsed notch.
public struct PeekPayload: Equatable, Sendable {
    public let id: String
    public let duration: Duration

    public init(id: String, duration: Duration = .seconds(2)) {
        self.id = id
        self.duration = duration
    }
}

public enum NotchMode: Equatable, Sendable {
    /// Collapsed to the bare notch silhouette.
    case closed
    /// Collapsed but widened to show a live activity.
    case peek(PeekPayload)
    /// Expanded because the pointer is here; closes when the pointer leaves.
    case open
    /// Expanded and held open until dismissed explicitly.
    case pinned

    /// Whether this mode draws the full expanded surface.
    public var isExpanded: Bool {
        switch self {
        case .open, .pinned: true
        case .closed, .peek: false
        }
    }
}

public struct NotchState: Equatable, Sendable {
    public var mode: NotchMode
    public var pointerInside: Bool

    public init(mode: NotchMode = .closed, pointerInside: Bool = false) {
        self.mode = mode
        self.pointerInside = pointerInside
    }

    public static let closed = NotchState()

    public var isExpanded: Bool { mode.isExpanded }
}
