import NotchCore
import Testing
@testable import LiveActivities

/// The wiring between an observer, a deriver and the callback — the part that is
/// the same in all three sources, checked on each of them because it is the part
/// that decides whether the notch ever shuts up.
@Suite("Live activity sources")
@MainActor
struct LiveActivitySourceTests {
    // MARK: Power

    @Test("starting seeds from the machine without announcing anything")
    func powerStartIsSilent() {
        let observer = FakeObserver(reading: PowerReading(percentage: 80, isPluggedIn: false))
        let source = PowerActivitySource(observer: observer)
        var announced: [PeekPayload] = []

        source.start { announced.append($0) }

        // Read once, to have something for the first real change to differ from.
        #expect(observer.reads == 1)
        #expect(announced.isEmpty)
    }

    @Test("a change the deriver considers news is announced")
    func powerAnnouncesTheCharger() {
        let observer = FakeObserver(reading: PowerReading(percentage: 80, isPluggedIn: false))
        let source = PowerActivitySource(observer: observer)
        var announced: [PeekPayload] = []
        source.start { announced.append($0) }

        observer.change(to: PowerReading(percentage: 80, isPluggedIn: true))

        #expect(announced.map(\.title) == ["Charging"])
    }

    @Test("a notification with nothing behind it announces nothing")
    func powerIgnoresEmptyNotifications() {
        let observer = FakeObserver(reading: PowerReading(percentage: 80, isPluggedIn: false))
        let source = PowerActivitySource(observer: observer)
        var announced: [PeekPayload] = []
        source.start { announced.append($0) }

        for _ in 0..<5 {
            observer.notifyWithoutChanging()
        }

        #expect(announced.isEmpty)
    }

    @Test("a machine with no battery announces nothing and is not asked to invent one")
    func powerWithoutABattery() {
        // A Mac mini. `read` returns nil and the deriver never sees a reading, so
        // there is no baseline to be wrong about later either.
        let observer = FakeObserver<PowerReading>(reading: nil)
        let source = PowerActivitySource(observer: observer)
        var announced: [PeekPayload] = []

        source.start { announced.append($0) }
        observer.notifyWithoutChanging()

        #expect(announced.isEmpty)
    }

    @Test("stopping stops the machine and the announcements")
    func powerStops() {
        let observer = FakeObserver(reading: PowerReading(percentage: 80, isPluggedIn: false))
        let source = PowerActivitySource(observer: observer)
        var announced: [PeekPayload] = []
        source.start { announced.append($0) }

        source.stop()
        observer.change(to: PowerReading(percentage: 80, isPluggedIn: true))

        #expect(observer.stops == 1)
        #expect(announced.isEmpty)
    }

    @Test("starting twice leaves one observer, not two")
    func powerStartIsIdempotent() {
        // Two registrations would mean two callbacks per change, and — worse — a
        // `stop` that only removes one of them.
        let observer = FakeObserver(reading: PowerReading(percentage: 80, isPluggedIn: false))
        let source = PowerActivitySource(observer: observer)

        source.start { _ in }
        source.start { _ in }

        #expect(observer.starts == 1)
    }

    // MARK: Audio devices

    private func reading(_ names: [String], output: String?) -> AudioDeviceReading {
        AudioDeviceReading(
            devices: names.map { AudioDevice(name: $0, transport: .bluetooth) },
            output: output
        )
    }

    @Test("what is already attached at launch is seeded, not announced")
    func audioDeviceStartIsSilent() {
        let observer = FakeObserver(reading: reading(["MacBook Pro Speakers"], output: "MacBook Pro Speakers"))
        let source = AudioDeviceSource(observer: observer)
        var announced: [PeekPayload] = []

        source.start { announced.append($0) }

        #expect(announced.isEmpty)
    }

    @Test("connecting a device announces it by name, once")
    func audioDeviceAnnouncesTheNewDevice() {
        let observer = FakeObserver(reading: reading(["MacBook Pro Speakers"], output: "MacBook Pro Speakers"))
        let source = AudioDeviceSource(observer: observer)
        var announced: [PeekPayload] = []
        source.start { announced.append($0) }

        observer.change(to: reading(["MacBook Pro Speakers", "AirPods Pro"], output: "MacBook Pro Speakers"))
        // The output moving to what just arrived is the same event arriving a
        // second time, and the system's own property churn is not an event at all.
        observer.change(to: reading(["MacBook Pro Speakers", "AirPods Pro"], output: "AirPods Pro"))
        observer.notifyWithoutChanging()
        observer.notifyWithoutChanging()

        #expect(announced.map(\.title) == ["AirPods Pro"])
        #expect(announced.map(\.detail) == ["Connected"])
    }

    @Test("stopping stops the device announcements")
    func audioDeviceStops() {
        let observer = FakeObserver(reading: reading(["MacBook Pro Speakers"], output: "MacBook Pro Speakers"))
        let source = AudioDeviceSource(observer: observer)
        var announced: [PeekPayload] = []
        source.start { announced.append($0) }

        source.stop()
        observer.change(to: reading(["MacBook Pro Speakers", "AirPods Pro"], output: "AirPods Pro"))

        #expect(observer.stops == 1)
        #expect(announced.isEmpty)
    }
}
