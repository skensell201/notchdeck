import Foundation

/// A transient notification shown beside the collapsed notch.
/// A transient announcement shown beside the collapsed notch.
///
/// Everything here is a plain value: `NotchCore` has no SwiftUI, so the payload
/// describes what to show and the shell decides how.
/// How an announcement is drawn.
public enum PeekStyle: Equatable, Sendable {
    /// The collapsed band widens and the words sit either side of the housing.
    case band
    /// A drop forms under the notch, breaks off, and carries the words itself.
    /// Reserved for events about a thing arriving or leaving, where the shape
    /// doing something physical is the announcement.
    case drop
}

/// What the detail line means. The only thing it decides is the colour, which
/// is why there is no case here for "it is just words".
public enum PeekTone: Equatable, Sendable {
    case neutral
    case positive
    case caution
}

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
    public var style: PeekStyle
    public var tone: PeekTone

    public init(
        id: String,
        duration: Duration = .seconds(2),
        symbolName: String = "bell",
        title: String = "",
        detail: String? = nil,
        level: Double? = nil,
        style: PeekStyle = .band,
        tone: PeekTone = .neutral
    ) {
        self.id = id
        self.duration = duration
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
        self.level = level.map { min(max($0, 0), 1) }
        self.style = style
        self.tone = tone
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
    /// An announcement falling out of the notch, kept apart from the mode on
    /// purpose: a drop is not a state the notch is in, it is something happening
    /// underneath it. That is what lets it fall while the panel is open, and
    /// what stops it collapsing a panel the user is in the middle of using.
    public var drop: PeekPayload?

    public init(mode: NotchMode = .closed, pointerInside: Bool = false, drop: PeekPayload? = nil) {
        self.mode = mode
        self.pointerInside = pointerInside
        self.drop = drop
    }

    public static let closed = NotchState()

    public var isExpanded: Bool { mode.isExpanded }
}
