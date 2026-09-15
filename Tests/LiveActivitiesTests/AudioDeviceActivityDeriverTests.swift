import NotchCore
import Testing
@testable import LiveActivities

@Suite("Audio device activities")
struct AudioDeviceActivityDeriverTests {
    private let speakers = AudioDevice(name: "MacBook Pro Speakers", transport: .builtIn)
    private let airPods = AudioDevice(name: "AirPods Pro", transport: .bluetooth)
    private let display = AudioDevice(name: "Studio Display", transport: .display)

    private func reading(_ devices: [AudioDevice], output: String?) -> AudioDeviceReading {
        AudioDeviceReading(devices: devices, output: output)
    }

    // MARK: The baseline

    @Test("everything already attached at launch is not announced")
    func firstReadingIsABaseline() {
        var deriver = AudioDeviceActivityDeriver()

        #expect(deriver.activity(for: reading([speakers, airPods], output: "AirPods Pro")) == nil)
    }

    // MARK: Arriving and leaving

    @Test("a device that appears announces itself as connected")
    func arrivalAnnouncesItself() {
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([speakers], output: "MacBook Pro Speakers"))

        let payload = deriver.activity(for: reading([speakers, airPods], output: "MacBook Pro Speakers"))

        #expect(payload?.title == "AirPods Pro")
        #expect(payload?.detail == "Connected")
        #expect(payload?.symbolName == "headphones")
        #expect(payload?.tone == .positive)
        // A drop, not a band: something arrived, and the shape says so.
        #expect(payload?.style == .drop)
        // The mode has to outlast the animation or the drop never lands.
        #expect(payload?.duration == NotchDropTiming.total)
    }

    @Test("a device that goes away announces itself as disconnected")
    func departureAnnouncesItself() {
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([speakers, airPods], output: "AirPods Pro"))

        let payload = deriver.activity(for: reading([speakers], output: "MacBook Pro Speakers"))

        #expect(payload?.title == "AirPods Pro")
        #expect(payload?.detail == "Disconnected")
        #expect(payload?.tone == .caution)
        // The device is gone and cannot be asked anything, so the symbol has to
        // come from what was known about it while it was here.
        #expect(payload?.symbolName == "headphones")
    }

    @Test("swapping one device for another announces the arrival")
    func arrivalWinsOverDeparture() {
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([speakers, airPods], output: "AirPods Pro"))

        let payload = deriver.activity(for: reading([speakers, display], output: "Studio Display"))

        #expect(payload?.title == "Studio Display")
        #expect(payload?.detail == "Connected")
    }

    // MARK: Sound moving on its own

    @Test("headphones that never left the list announce when they take the sound back")
    func outputMovingIsItsOwnEvent() {
        // Plenty of Bluetooth headphones stay in the device list while they are
        // off the head. Nothing arrives, nothing leaves, and the only thing that
        // says the user just put them on is where sound went.
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([speakers, airPods], output: "MacBook Pro Speakers"))

        let payload = deriver.activity(for: reading([speakers, airPods], output: "AirPods Pro"))

        #expect(payload?.title == "AirPods Pro")
        #expect(payload?.detail == "Audio Output")
        #expect(payload?.tone == .neutral)
        #expect(payload?.style == .drop)
    }

    @Test("the sound moving to a device that just connected is the same event, not a second one")
    func arrivalSwallowsItsOwnOutputMove() {
        // The list changes first and the output follows a moment later, so this
        // is one connection arriving twice.
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([speakers], output: "MacBook Pro Speakers"))
        _ = deriver.activity(for: reading([speakers, airPods], output: "MacBook Pro Speakers"))

        #expect(deriver.activity(for: reading([speakers, airPods], output: "AirPods Pro")) == nil)
    }

    @Test("the sound landing elsewhere after a disconnection is not a second announcement")
    func departureSwallowsItsOwnOutputMove() {
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([speakers, airPods], output: "AirPods Pro"))
        _ = deriver.activity(for: reading([speakers], output: "MacBook Pro Speakers"))

        #expect(deriver.activity(for: reading([speakers], output: "MacBook Pro Speakers")) == nil)
    }

    // MARK: The no-op cases

    @Test("the same reading again announces nothing, however often the listener fires")
    func unchangedReadingIsNotNews() {
        // Both listeners fire for reasons that have nothing to do with a device
        // arriving: a property touched on one of them, a sample rate changing,
        // the machine waking.
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([speakers, airPods], output: "AirPods Pro"))

        for _ in 0..<10 {
            #expect(deriver.activity(for: reading([airPods, speakers], output: "AirPods Pro")) == nil)
        }
    }

    @Test("headphones listed twice, once per direction, announce once")
    func duplicateNamesAnnounceOnce() {
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([speakers], output: "MacBook Pro Speakers"))

        let both = reading([speakers, airPods, airPods], output: "MacBook Pro Speakers")
        #expect(deriver.activity(for: both)?.title == "AirPods Pro")
        #expect(deriver.activity(for: both) == nil)
    }

    @Test("a device that reports no name is a failed read, not a device")
    func namelessDevicesAreIgnored() {
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([speakers], output: "MacBook Pro Speakers"))

        let blank = AudioDevice(name: "  ", transport: .other)
        #expect(deriver.activity(for: reading([speakers, blank], output: "MacBook Pro Speakers")) == nil)
        // And it does not count as a departure the next time round either.
        #expect(deriver.activity(for: reading([speakers], output: "MacBook Pro Speakers")) == nil)
    }

    @Test("a machine left with no output at all announces nothing extra")
    func noOutputIsNotAnEvent() {
        var deriver = AudioDeviceActivityDeriver()
        _ = deriver.activity(for: reading([airPods], output: "AirPods Pro"))

        // The only device is unplugged: that is the disconnection, and the
        // absence of any output afterwards is not a second thing to say.
        #expect(deriver.activity(for: reading([], output: nil))?.detail == "Disconnected")
        #expect(deriver.activity(for: reading([], output: nil)) == nil)
    }
}
