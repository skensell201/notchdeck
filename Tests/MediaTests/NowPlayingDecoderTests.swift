import Foundation
import Testing
@testable import Media

@Suite("Now playing decoder")
struct NowPlayingDecoderTests {
    private let priming = #"{"type":"data","diff":false,"payload":{}}"#

    private let snapshot = """
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome",\
    "title":"Spike Test Track","artist":"NotchDeck Spike","album":"MediaRemote Probe",\
    "playing":true,"playbackRate":1,"elapsedTimeMicros":0,"durationMicros":125014014,\
    "timestampEpochMicros":1788357423000000,"contentItemIdentifier":"ABC"}}
    """

    @Test("the priming line yields no snapshot")
    func primingIsIgnored() {
        var decoder = NowPlayingDecoder()

        #expect(decoder.consume(line: priming) == nil)
    }

    @Test("a full payload becomes a snapshot")
    func fullSnapshot() throws {
        var decoder = NowPlayingDecoder()

        let consumed = decoder.consume(line: snapshot)
        let state = try #require(consumed)

        #expect(state.bundleIdentifier == "com.google.Chrome")
        #expect(state.title == "Spike Test Track")
        #expect(state.artist == "NotchDeck Spike")
        #expect(state.isPlaying)
        #expect(state.playbackRate == 1)
        #expect(state.durationMicros == 125_014_014)
    }

    @Test("a diff changes only the keys it carries")
    func diffMerges() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        let consumed = decoder.consume(
            line: #"{"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0}}"#
        )
        let state = try #require(consumed)

        #expect(!state.isPlaying)
        #expect(state.playbackRate == 0)
        #expect(state.title == "Spike Test Track")
        #expect(state.artist == "NotchDeck Spike")
    }

    @Test("an explicit null in a diff clears that field")
    func explicitNullClears() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        let consumed = decoder.consume(
            line: #"{"type":"data","diff":true,"payload":{"artist":null}}"#
        )
        let state = try #require(consumed)

        #expect(state.artist == nil)
        #expect(state.album == "MediaRemote Probe")
    }

    @Test("a full payload replaces the state rather than merging into it")
    func fullPayloadReplaces() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        let consumed = decoder.consume(
            line: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","title":"Other","playing":true}}"#
        )
        let state = try #require(consumed)

        #expect(state.title == "Other")
        #expect(state.artist == nil)
        #expect(state.album == nil)
    }

    @Test("a payload missing any required field yields no snapshot")
    func requiredFieldsAreRequired() {
        var decoder = NowPlayingDecoder()

        #expect(decoder.consume(
            line: #"{"type":"data","diff":false,"payload":{"title":"No bundle id","playing":true}}"#
        ) == nil)
    }

    @Test("a sparse payload with only the required fields still yields a snapshot")
    func sparsePayload() throws {
        var decoder = NowPlayingDecoder()

        let consumed = decoder.consume(
            line: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"org.telegram","title":"Voice","playing":true}}"#
        )
        let state = try #require(consumed)

        #expect(state.artist == nil)
        #expect(state.album == nil)
        #expect(state.durationMicros == nil)
        #expect(state.playbackRate == 0)
    }

    @Test("artwork arriving in a later diff is attached to the existing track")
    func lateArtwork() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        let consumed = decoder.consume(
            line: #"{"type":"data","diff":true,"payload":{"artworkData":"QUJD","artworkMimeType":"image/jpeg"}}"#
        )
        let state = try #require(consumed)

        #expect(state.artwork?.data == Data("ABC".utf8))
        #expect(state.artwork?.mimeType == "image/jpeg")
    }

    @Test("a diff arriving before any snapshot is applied to an empty state")
    func diffBeforeSnapshot() {
        var decoder = NowPlayingDecoder()

        #expect(decoder.consume(line: #"{"type":"data","diff":true,"payload":{"playing":false}}"#) == nil)
    }

    @Test("a literal null document clears everything")
    func literalNullClears() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        #expect(decoder.consume(line: "null") == nil)
        #expect(decoder.snapshot == nil)
    }

    @Test("malformed input leaves the previous snapshot untouched")
    func malformedIsIgnored() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        #expect(decoder.consume(line: "{not json") == nil)
        #expect(decoder.snapshot?.title == "Spike Test Track")
    }

    @Test("a blank line is ignored")
    func blankLineIsIgnored() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        #expect(decoder.consume(line: "   ") == nil)
        #expect(decoder.snapshot != nil)
    }
}
