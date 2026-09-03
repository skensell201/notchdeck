import Foundation

/// Merges the adapter's diff protocol into a running snapshot.
///
/// `diff:false` payloads replace the state outright; `diff:true` payloads merge,
/// with an explicit null clearing a field. A snapshot is produced only once the
/// two dependable fields — `title` and `playing` — are both known. `bundleIdentifier`
/// is not required: the adapter itself only sends it when the now-playing process
/// resolves to an `NSRunningApplication` with a bundle id.
public struct NowPlayingDecoder {
    private struct Partial: Equatable {
        var bundleIdentifier: String?
        var processIdentifier: Int32?
        var title: String?
        var playing: Bool?
        var artist: String?
        var album: String?
        var contentItemIdentifier: String?
        var playbackRate: Double?
        var elapsedTimeMicros: Int64?
        var durationMicros: Int64?
        var timestampEpochMicros: Int64?
        /// Decoded once, when `artworkData` arrives as `.set` — not re-decoded on
        /// every subsequent line, most of which don't touch artwork at all.
        var artworkData: Data?
        var artworkMimeType: String?
    }

    private var partial = Partial()
    public private(set) var snapshot: NowPlaying?

    public init() {}

    /// Consumes one line of the stream. Returns the new snapshot when the line
    /// produced one, and nil when it did not — a priming line, a line that leaves
    /// the state incomplete, or unparseable input.
    @discardableResult
    public mutating func consume(line: String) -> NowPlaying? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "null" {
            partial = Partial()
            snapshot = nil
            return nil
        }

        guard let data = trimmed.data(using: .utf8),
              let line = try? JSONDecoder().decode(StreamLine.self, from: data) else {
            return nil
        }

        if !line.diff {
            partial = Partial()
        }
        apply(line.payload)
        snapshot = project()
        return snapshot
    }

    private mutating func apply(_ delta: PayloadDelta) {
        partial.bundleIdentifier = delta.bundleIdentifier.applied(to: partial.bundleIdentifier)
        partial.processIdentifier = delta.processIdentifier.applied(to: partial.processIdentifier)
        partial.title = delta.title.applied(to: partial.title)
        partial.playing = delta.playing.applied(to: partial.playing)
        partial.artist = delta.artist.applied(to: partial.artist)
        partial.album = delta.album.applied(to: partial.album)
        partial.contentItemIdentifier = delta.contentItemIdentifier.applied(to: partial.contentItemIdentifier)
        partial.playbackRate = delta.playbackRate.applied(to: partial.playbackRate)
        partial.elapsedTimeMicros = delta.elapsedTimeMicros.applied(to: partial.elapsedTimeMicros)
        partial.durationMicros = delta.durationMicros.applied(to: partial.durationMicros)
        partial.timestampEpochMicros = delta.timestampEpochMicros.applied(to: partial.timestampEpochMicros)
        partial.artworkMimeType = delta.artworkMimeType.applied(to: partial.artworkMimeType)

        switch delta.artworkData {
        case .unchanged:
            break
        case .cleared:
            partial.artworkData = nil
        case .set(let base64):
            // Base64-decode once, here, rather than on every `project()` call —
            // most lines are single-key diffs that never touch artwork.
            partial.artworkData = Data(base64Encoded: base64)
        }
    }

    private func project() -> NowPlaying? {
        guard let title = partial.title,
              let playing = partial.playing else {
            return nil
        }

        var artwork: NowPlaying.Artwork?
        if let data = partial.artworkData {
            artwork = NowPlaying.Artwork(data: data, mimeType: partial.artworkMimeType)
        }

        return NowPlaying(
            bundleIdentifier: partial.bundleIdentifier,
            processIdentifier: partial.processIdentifier,
            title: title,
            isPlaying: playing,
            artist: partial.artist,
            album: partial.album,
            contentItemIdentifier: partial.contentItemIdentifier,
            artwork: artwork,
            playbackRate: partial.playbackRate ?? 0,
            elapsedTimeMicros: partial.elapsedTimeMicros,
            durationMicros: partial.durationMicros,
            timestampEpochMicros: partial.timestampEpochMicros
        )
    }
}
