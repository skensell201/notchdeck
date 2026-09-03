import Foundation

/// A transient notification shown beside the collapsed notch.
/// A transient announcement shown beside the collapsed notch.
///
/// Everything here is a plain value: `NotchCore` has no SwiftUI, so the payload
/// describes what to show and the shell decides how.
public struct PeekPayload: Equatable, Sendable {
    /// Identity, not text. Two activities with the same id replace each other,
    /// which is what makes a held volume key show one bar rather than a queue.
    public let id: String
    public let duration: Duration
    public var symbolName: String
    public var title: String
    public var detail: String?
    /// A level between zero and one for the things that have one — volume, a
    /// battery percentage. Nil for announcements that are just an event.
    public var level: Double?

    public init(
        id: String,
        duration: Duration = .seconds(2),
        symbolName: String = "bell",
        title: String = "",
        detail: String? = nil,
        level: Double? = nil
    ) {
        self.id = id
        self.duration = duration
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
        self.level = level.map { min(max($0, 0), 1) }
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
