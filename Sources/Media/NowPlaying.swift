import Foundation

/// A now-playing snapshot.
///
/// Only `bundleIdentifier`, `title` and `isPlaying` are dependable: the adapter's
/// key set varies by player, and browsers in particular omit most of the rest.
public struct NowPlaying: Equatable, Sendable {
    public struct Artwork: Equatable, Sendable {
        public var data: Data
        public var mimeType: String?
    }

    public var bundleIdentifier: String
    public var title: String
    public var isPlaying: Bool

    public var artist: String?
    public var album: String?
    public var contentItemIdentifier: String?
    public var artwork: Artwork?

    /// Zero while paused. Drives position interpolation — use this, not `isPlaying`.
    public var playbackRate: Double
    public var elapsedTimeMicros: Int64?
    public var durationMicros: Int64?
    /// When `elapsedTimeMicros` was measured, in epoch microseconds.
    public var timestampEpochMicros: Int64?
}
