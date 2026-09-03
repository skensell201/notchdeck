import Testing
@testable import Media

final class RecordingRunner: AdapterCommandRunner, @unchecked Sendable {
    var invocations: [[String]] = []
    var result = true

    func run(arguments: [String]) async -> Bool {
        invocations.append(arguments)
        return result
    }
}

final class RecordingKeyPoster: MediaKeyPoster, @unchecked Sendable {
    var posted: [Int32] = []

    func post(keyCode: Int32) {
        posted.append(keyCode)
    }
}

@Suite("Media commands")
struct MediaCommandsTests {
    @Test("each transport action maps to the adapter's command id")
    func adapterCommandIDs() async {
        let runner = RecordingRunner()
        let commands = MediaCommands(adapter: runner, keys: RecordingKeyPoster())

        for action in [TransportAction.play, .pause, .toggle, .next, .previous] {
            await commands.perform(action)
        }

        #expect(runner.invocations == [
            ["send", "0"], ["send", "1"], ["send", "2"], ["send", "4"], ["send", "5"]
        ])
    }

    @Test("a successful adapter command does not also post a media key")
    func noDoubleDispatch() async {
        let keys = RecordingKeyPoster()
        let commands = MediaCommands(adapter: RecordingRunner(), keys: keys)

        await commands.perform(.next)

        #expect(keys.posted.isEmpty)
    }

    @Test("a failing adapter command falls back to the media key")
    func fallsBackOnFailure() async {
        let runner = RecordingRunner()
        runner.result = false
        let keys = RecordingKeyPoster()
        let commands = MediaCommands(adapter: runner, keys: keys)

        await commands.perform(.next)

        #expect(keys.posted == [TransportAction.next.mediaKeyCode])
    }

    @Test("with no adapter at all, every action goes straight to a media key")
    func noAdapterUsesKeys() async {
        let keys = RecordingKeyPoster()
        let commands = MediaCommands(adapter: nil, keys: keys)

        await commands.perform(.play)
        await commands.perform(.previous)

        #expect(keys.posted == [16, 18])
    }

    @Test("play, pause and toggle all use the play media key")
    func transportKeysCollapse() {
        #expect(TransportAction.play.mediaKeyCode == 16)
        #expect(TransportAction.pause.mediaKeyCode == 16)
        #expect(TransportAction.toggle.mediaKeyCode == 16)
        #expect(TransportAction.next.mediaKeyCode == 17)
        #expect(TransportAction.previous.mediaKeyCode == 18)
    }

    @Test("seek passes microseconds to the adapter")
    func seekUsesMicroseconds() async {
        let runner = RecordingRunner()
        let commands = MediaCommands(adapter: runner, keys: RecordingKeyPoster())

        let succeeded = await commands.seek(toMicros: 60_000_000)

        #expect(succeeded)
        #expect(runner.invocations == [["seek", "60000000"]])
    }

    @Test("seek reports failure rather than falling back, because no media key can seek")
    func seekHasNoFallback() async {
        let keys = RecordingKeyPoster()
        let commands = MediaCommands(adapter: nil, keys: keys)

        let succeeded = await commands.seek(toMicros: 1_000)

        #expect(!succeeded)
        #expect(keys.posted.isEmpty)
    }
}
