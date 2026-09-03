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

    // MARK: Volume

    @Test("the volume at launch is seeded, not announced")
    func volumeStartIsSilent() {
        let observer = FakeObserver(reading: VolumeReading(level: 0.4, isMuted: false))
        let source = VolumeActivitySource(observer: observer)
        var announced: [PeekPayload] = []

        source.start { announced.append($0) }

        #expect(announced.isEmpty)
    }

    @Test("one volume change announces once, however many times CoreAudio says so")
    func volumeAnnouncesOncePerChange() {
        let observer = FakeObserver(reading: VolumeReading(level: 0.4, isMuted: false))
        let source = VolumeActivitySource(observer: observer)
        var announced: [PeekPayload] = []
        source.start { announced.append($0) }

        observer.change(to: VolumeReading(level: 0.5, isMuted: false))
        // The second callback CoreAudio makes for the same change.
        observer.notifyWithoutChanging()

        #expect(announced.map(\.level) == [0.5])
    }

    @Test("stopping stops the volume announcements")
    func volumeStops() {
        let observer = FakeObserver(reading: VolumeReading(level: 0.4, isMuted: false))
        let source = VolumeActivitySource(observer: observer)
        var announced: [PeekPayload] = []
        source.start { announced.append($0) }

        source.stop()
        observer.change(to: VolumeReading(level: 0.9, isMuted: false))

        #expect(observer.stops == 1)
        #expect(announced.isEmpty)
    }

    // MARK: Output device

    @Test("the device in use at launch is seeded, not announced")
    func outputDeviceStartIsSilent() {
        let observer = FakeObserver(
            reading: OutputDeviceReading(name: "MacBook Pro Speakers", transport: .builtIn)
        )
        let source = OutputDeviceActivitySource(observer: observer)
        var announced: [PeekPayload] = []

        source.start { announced.append($0) }

        #expect(announced.isEmpty)
    }

    @Test("connecting a device announces it by name, once")
    func outputDeviceAnnouncesTheNewDevice() {
        let observer = FakeObserver(
            reading: OutputDeviceReading(name: "MacBook Pro Speakers", transport: .builtIn)
        )
        let source = OutputDeviceActivitySource(observer: observer)
        var announced: [PeekPayload] = []
        source.start { announced.append($0) }

        observer.change(to: OutputDeviceReading(name: "AirPods Pro", transport: .bluetooth))
        // Property churn on the same device afterwards.
        observer.notifyWithoutChanging()
        observer.notifyWithoutChanging()

        #expect(announced.map(\.title) == ["AirPods Pro"])
    }

    @Test("stopping stops the device announcements")
    func outputDeviceStops() {
        let observer = FakeObserver(
            reading: OutputDeviceReading(name: "MacBook Pro Speakers", transport: .builtIn)
        )
        let source = OutputDeviceActivitySource(observer: observer)
        var announced: [PeekPayload] = []
        source.start { announced.append($0) }

        source.stop()
        observer.change(to: OutputDeviceReading(name: "AirPods Pro", transport: .bluetooth))

        #expect(observer.stops == 1)
        #expect(announced.isEmpty)
    }
}
