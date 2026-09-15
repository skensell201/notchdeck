import Foundation
import NotchCore

/// How a device is attached, in the terms CoreAudio uses.
///
/// Only the cases that change which symbol is drawn are named; everything else
/// is `other`, which is a speaker. Kept as a Swift enum rather than the raw
/// four-character codes so the mapping can be tested without CoreAudio.
public enum AudioTransport: Sendable, Equatable {
    case builtIn
    case bluetooth
    case airPlay
    case display
    case other
}

/// One audio device as the machine lists it.
///
/// Identity is the name, not the CoreAudio object ID: the ID is what the HAL
/// hands out and reuses, and the name is what the user would recognise as the
/// thing they just plugged in.
public struct AudioDevice: Sendable, Equatable {
    public var name: String
    public var transport: AudioTransport

    public init(name: String, transport: AudioTransport) {
        self.name = name
        self.transport = transport
    }
}

/// Everything about the machine's audio at one moment: what is attached, and
/// where sound is going.
///
/// Both halves in one reading on purpose. Connecting headphones changes both at
/// the same instant, and two sources watching one half each would announce the
/// same event twice and race over which one the notch ended up showing.
public struct AudioDeviceReading: Sendable, Equatable {
    public var devices: [AudioDevice]
    /// The name of the default output device, or nil on a machine with no
    /// output at all — which happens for real, the moment the only one is
    /// unplugged.
    public var output: String?

    public init(devices: [AudioDevice], output: String?) {
        self.devices = devices
        self.output = output
    }
}

/// Announces devices arriving, leaving, and taking over the sound.
///
/// Three events, one subject, one announcement each. Which of them happened is
/// decided by comparing a whole reading against the one before it rather than
/// by trusting the notification that woke us: CoreAudio fires for reasons that
/// have nothing to do with anything the user would notice.
public struct AudioDeviceActivityDeriver: Sendable {
    static let id = "audio-device"

    /// Every device seen last time, by name, with the transport that decides its
    /// symbol. A device that has gone away cannot be asked for either.
    ///
    /// Nil before the first reading: whatever is attached at launch has not just
    /// connected.
    private var known: [String: AudioTransport]?
    private var output: String?
    /// The device whose arrival was just announced, until the sound catches up
    /// with it. The system moves the output a moment after the device list says
    /// the device exists, and that move is the tail of the connection rather
    /// than a second event.
    private var announcedArrival: String?

    public init() {}

    public mutating func activity(for reading: AudioDeviceReading) -> PeekPayload? {
        // A device that reports no name is a failed read, not a device.
        let named = reading.devices.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var current: [String: AudioTransport] = [:]
        // Headphones list themselves twice, once per direction. They connected
        // once, so they announce once.
        for device in named where current[device.name] == nil {
            current[device.name] = device.transport
        }

        guard let known else {
            self.known = current
            output = reading.output
            return nil
        }
        self.known = current

        // Arrivals first: swapping one device for another is far more often read
        // as "this connected" than as "that went away".
        if let arrived = named.first(where: { known[$0.name] == nil }) {
            output = reading.output
            announcedArrival = arrived.name
            return payload(arrived.name, arrived.transport, .connected)
        }

        // Sorted so that two devices leaving at once — a dock unplugged — always
        // announce the same one.
        if let gone = known.keys.filter({ current[$0] == nil }).sorted().first {
            output = reading.output
            announcedArrival = nil
            return payload(gone, known[gone] ?? .other, .disconnected)
        }

        let previous = output
        output = reading.output
        guard let now = reading.output, now != previous else { return nil }

        // Whichever way this move goes, the connection it might belong to is
        // finished being announced.
        let finishesAConnection = now == announcedArrival
        announcedArrival = nil
        guard !finishesAConnection else { return nil }

        // Nothing came or went, so this is the user sending sound elsewhere —
        // or headphones that never left the list taking it back.
        return payload(now, current[now] ?? .other, .moved)
    }

    private enum Event {
        case connected
        case disconnected
        case moved

        var detail: String {
            switch self {
            case .connected: "Connected"
            case .disconnected: "Disconnected"
            case .moved: "Audio Output"
            }
        }

        var tone: PeekTone {
            switch self {
            case .connected: .positive
            case .disconnected: .caution
            // Sound moving between devices that are both still there is not good
            // news or bad news, it is just where sound is now.
            case .moved: .neutral
            }
        }
    }

    private func payload(_ name: String, _ transport: AudioTransport, _ event: Event) -> PeekPayload {
        PeekPayload(
            id: Self.id,
            // The mode has to outlast the animation, or the drop is removed
            // mid-fall and never lands.
            duration: NotchDropTiming.total,
            symbolName: Self.symbolName(for: transport),
            title: name,
            detail: event.detail,
            style: .drop,
            tone: event.tone
        )
    }

    static func symbolName(for transport: AudioTransport) -> String {
        switch transport {
        // Bluetooth output is headphones far more often than not, and AirPods
        // announcing themselves is the reason this source exists.
        case .bluetooth: "headphones"
        case .builtIn: "laptopcomputer"
        case .airPlay: "airplayaudio"
        case .display: "display"
        case .other: "hifispeaker.fill"
        }
    }
}
