import Foundation
import NotchCore

/// How the current output device is attached, in the terms CoreAudio uses.
///
/// Only the cases that change which symbol is drawn are named; everything else
/// is `other`, which is a speaker. Kept as a Swift enum rather than the raw
/// four-character codes so the mapping below can be tested without CoreAudio.
public enum AudioTransport: Sendable, Equatable {
    case builtIn
    case bluetooth
    case airPlay
    case display
    case other
}

/// The output device at one moment.
public struct OutputDeviceReading: Sendable, Equatable {
    /// What the device calls itself — "AirPods Pro", "MacBook Pro Speakers".
    /// This is the announcement.
    public var name: String
    public var transport: AudioTransport

    public init(name: String, transport: AudioTransport) {
        self.name = name
        self.transport = transport
    }
}

/// Announces the output device when it actually changes.
///
/// The CoreAudio listener on the default device fires for reasons that have
/// nothing to do with the device changing — a device being added or removed
/// elsewhere in the system, a property on the same device being touched — so the
/// name the user would read is the only honest test of whether anything
/// happened.
public struct OutputDeviceActivityDeriver: Sendable {
    /// Long enough to read a device name, which is the entire content.
    public static let duration: Duration = .seconds(2)

    static let id = "output-device"

    /// The name last seen. Nil before the first reading: whatever the machine is
    /// playing through at launch is not something that just changed.
    private var previous: String?

    public init() {}

    public mutating func activity(for reading: OutputDeviceReading) -> PeekPayload? {
        let name = reading.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A device that reports no name is a failed read, not a new device. Leave
        // the previous name in place so the real one still announces when it
        // arrives a moment later.
        guard !name.isEmpty else { return nil }

        let last = previous
        previous = name
        guard let last else { return nil }
        guard name != last else { return nil }

        return PeekPayload(
            id: Self.id,
            duration: Self.duration,
            symbolName: Self.symbolName(for: reading.transport),
            title: name,
            detail: "Audio Output"
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

