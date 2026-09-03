import Foundation

/// One field in a stream payload. The protocol distinguishes a key that was not
/// sent from one sent as an explicit null, and they mean different things:
/// absent leaves the value alone, null clears it.
public enum FieldUpdate<Value: Equatable & Sendable>: Equatable, Sendable {
    case unchanged
    case cleared
    case set(Value)

    /// Applies this update to an existing value.
    public func applied(to current: Value?) -> Value? {
        switch self {
        case .unchanged: current
        case .cleared: nil
        case .set(let value): value
        }
    }
}

/// The `payload` object of one stream line.
struct PayloadDelta: Decodable {
    var bundleIdentifier: FieldUpdate<String> = .unchanged
    var title: FieldUpdate<String> = .unchanged
    var artist: FieldUpdate<String> = .unchanged
    var album: FieldUpdate<String> = .unchanged
    var contentItemIdentifier: FieldUpdate<String> = .unchanged
    var playing: FieldUpdate<Bool> = .unchanged
    var playbackRate: FieldUpdate<Double> = .unchanged
    var elapsedTimeMicros: FieldUpdate<Int64> = .unchanged
    var durationMicros: FieldUpdate<Int64> = .unchanged
    var timestampEpochMicros: FieldUpdate<Int64> = .unchanged
    var artworkData: FieldUpdate<String> = .unchanged
    var artworkMimeType: FieldUpdate<String> = .unchanged

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, title, artist, album, contentItemIdentifier
        case playing, playbackRate, elapsedTimeMicros, durationMicros
        case timestampEpochMicros, artworkData, artworkMimeType
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func update<T: Decodable & Equatable & Sendable>(_ key: CodingKeys) throws -> FieldUpdate<T> {
            guard container.contains(key) else { return .unchanged }
            if try container.decodeNil(forKey: key) { return .cleared }
            return .set(try container.decode(T.self, forKey: key))
        }

        bundleIdentifier = try update(.bundleIdentifier)
        title = try update(.title)
        artist = try update(.artist)
        album = try update(.album)
        contentItemIdentifier = try update(.contentItemIdentifier)
        playing = try update(.playing)
        playbackRate = try update(.playbackRate)
        elapsedTimeMicros = try update(.elapsedTimeMicros)
        durationMicros = try update(.durationMicros)
        timestampEpochMicros = try update(.timestampEpochMicros)
        artworkData = try update(.artworkData)
        artworkMimeType = try update(.artworkMimeType)
    }
}

struct StreamLine: Decodable {
    var diff: Bool
    var payload: PayloadDelta
}
