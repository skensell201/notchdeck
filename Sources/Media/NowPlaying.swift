import Foundation

/// A now-playing snapshot.
///
/// Only `title` and `isPlaying` are dependable: the adapter's own mandatory-key
/// list is `processIdentifier`, `title`, `playing` — `bundleIdentifier` is present
/// only when the now-playing process resolves to an `NSRunningApplication` with a
/// bundle id, which a CLI player such as `mpv` never does even while it is
/// genuinely playing.
public struct NowPlaying: Equatable, Sendable {
    public struct Artwork: Equatable, Sendable {
        public var data: Data
        public var mimeType: String?
    }

    public var bundleIdentifier: String?
    public var processIdentifier: Int32?
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
