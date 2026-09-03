import CoreAudio
import Testing
@testable import LiveActivities

@Suite("Output device activities")
struct OutputDeviceActivityDeriverTests {
    private func reading(_ name: String, _ transport: AudioTransport = .builtIn) -> OutputDeviceReading {
        OutputDeviceReading(name: name, transport: transport)
    }

    // MARK: The baseline

    @Test("the device already in use at launch is not announced")
    func firstReadingIsABaseline() {
        var deriver = OutputDeviceActivityDeriver()

        #expect(deriver.activity(for: reading("MacBook Pro Speakers")) == nil)
    }

    @Test("a new device announces itself by name")
    func newDeviceAnnouncesItsName() {
        var deriver = OutputDeviceActivityDeriver()
        _ = deriver.activity(for: reading("MacBook Pro Speakers"))

        let payload = deriver.activity(for: reading("AirPods Pro", .bluetooth))

        #expect(payload?.id == "output-device")
        #expect(payload?.title == "AirPods Pro")
        #expect(payload?.detail == "Audio Output")
        #expect(payload?.symbolName == "headphones")
        // Nothing here has a level; the bar would be meaningless.
        #expect(payload?.level == nil)
    }

    // MARK: The no-op cases

    @Test("the same device again announces nothing, however often the listener fires")
    func unchangedNameIsNotNews() {
        // The default-output-device listener fires on unrelated property churn —
        // a device appearing elsewhere, a property touched on this one — and none
        // of that is a device change.
        var deriver = OutputDeviceActivityDeriver()
        _ = deriver.activity(for: reading("AirPods Pro", .bluetooth))

        for _ in 0..<10 {
            #expect(deriver.activity(for: reading("AirPods Pro", .bluetooth)) == nil)
        }
    }

    @Test("a name that differs only in padding is the same name")
    func paddedNameIsNotNews() {
        var deriver = OutputDeviceActivityDeriver()
        _ = deriver.activity(for: reading("AirPods Pro"))

        #expect(deriver.activity(for: reading("  AirPods Pro  ")) == nil)
    }

    @Test("the same device reporting a different transport announces nothing")
    func transportChangeAloneIsNotNews() {
        // The name is what the user reads, so the name is what decides. A device
        // re-reporting itself over a different transport is not a new device.
        var deriver = OutputDeviceActivityDeriver()
        _ = deriver.activity(for: reading("Studio Display", .display))

        #expect(deriver.activity(for: reading("Studio Display", .other)) == nil)
    }

    @Test("a nameless reading announces nothing and does not become the baseline")
    func namelessReadingIsAFailedRead() {
        var deriver = OutputDeviceActivityDeriver()
        _ = deriver.activity(for: reading("MacBook Pro Speakers"))

        // A device mid-connection can report an empty name for a moment. That is
        // a read that failed, not a device called nothing — and the real name
        // arriving afterwards must still announce.
        #expect(deriver.activity(for: reading("")) == nil)
        #expect(deriver.activity(for: reading("   ")) == nil)
        #expect(deriver.activity(for: reading("AirPods Pro"))?.title == "AirPods Pro")
    }

    @Test("switching away and back announces both times")
    func switchingBackAnnouncesAgain() {
        var deriver = OutputDeviceActivityDeriver()
        _ = deriver.activity(for: reading("MacBook Pro Speakers"))

        #expect(deriver.activity(for: reading("AirPods Pro", .bluetooth)) != nil)
        #expect(deriver.activity(for: reading("MacBook Pro Speakers")) != nil)
    }

    // MARK: The symbol

    @Test("the symbol follows how the device is attached")
    func symbolFollowsTransport() {
        #expect(OutputDeviceActivityDeriver.symbolName(for: .bluetooth) == "headphones")
        #expect(OutputDeviceActivityDeriver.symbolName(for: .builtIn) == "laptopcomputer")
        #expect(OutputDeviceActivityDeriver.symbolName(for: .airPlay) == "airplayaudio")
        #expect(OutputDeviceActivityDeriver.symbolName(for: .display) == "display")
        #expect(OutputDeviceActivityDeriver.symbolName(for: .other) == "hifispeaker.fill")
    }

    @Test("CoreAudio's transport codes reduce to the handful that change the symbol")
    func transportCodes() {
        #expect(SystemOutputDeviceObserver.transport(kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        #expect(SystemOutputDeviceObserver.transport(kAudioDeviceTransportTypeBluetooth) == .bluetooth)
        // Classic and LE are the same thing to whoever is wearing them.
        #expect(SystemOutputDeviceObserver.transport(kAudioDeviceTransportTypeBluetoothLE) == .bluetooth)
        #expect(SystemOutputDeviceObserver.transport(kAudioDeviceTransportTypeAirPlay) == .airPlay)
        #expect(SystemOutputDeviceObserver.transport(kAudioDeviceTransportTypeHDMI) == .display)
        #expect(SystemOutputDeviceObserver.transport(kAudioDeviceTransportTypeUSB) == .other)
        // A device that does not say how it is attached is still a device.
        #expect(SystemOutputDeviceObserver.transport(nil) == .other)
    }
}
