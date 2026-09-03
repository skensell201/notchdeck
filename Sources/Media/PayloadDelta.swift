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
    var processIdentifier: FieldUpdate<Int32> = .unchanged
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
        case bundleIdentifier, processIdentifier, title, artist, album, contentItemIdentifier
        case playing, playbackRate, elapsedTimeMicros, durationMicros
        case timestampEpochMicros, artworkData, artworkMimeType
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // A key that is present but decodes as the wrong type (e.g. the adapter
        // sending a string where a number is expected) is treated as `.unchanged`
        // rather than failing the whole line — one malformed field must not
        // discard the dependable ones alongside it.
        func update<T: Decodable & Equatable & Sendable>(_ key: CodingKeys) -> FieldUpdate<T> {
            guard container.contains(key) else { return .unchanged }
            if (try? container.decodeNil(forKey: key)) == true { return .cleared }
            guard let value = try? container.decode(T.self, forKey: key) else { return .unchanged }
            return .set(value)
        }

        bundleIdentifier = update(.bundleIdentifier)
        processIdentifier = update(.processIdentifier)
        title = update(.title)
        artist = update(.artist)
        album = update(.album)
        contentItemIdentifier = update(.contentItemIdentifier)
        playing = update(.playing)
        playbackRate = update(.playbackRate)
        elapsedTimeMicros = update(.elapsedTimeMicros)
        durationMicros = update(.durationMicros)
        timestampEpochMicros = update(.timestampEpochMicros)
        artworkData = update(.artworkData)
        artworkMimeType = update(.artworkMimeType)
    }
}

struct StreamLine: Decodable {
    var diff: Bool
    var payload: PayloadDelta
}
