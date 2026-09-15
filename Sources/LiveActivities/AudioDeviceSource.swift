import CoreAudio
import Foundation
import NotchCore

/// Announces audio devices connecting, disconnecting, and taking over the sound.
@MainActor
public final class AudioDeviceSource: LiveActivitySource {
    private let observer: any MachineObserving<AudioDeviceReading>
    private var deriver: AudioDeviceActivityDeriver
    private var emit: ((PeekPayload) -> Void)?

    public init(
        observer: any MachineObserving<AudioDeviceReading> = SystemAudioDeviceObserver(),
        deriver: AudioDeviceActivityDeriver = AudioDeviceActivityDeriver()
    ) {
        self.observer = observer
        self.deriver = deriver
    }

    public func start(emit: @escaping (PeekPayload) -> Void) {
        guard self.emit == nil else { return }
        self.emit = emit
        observer.start { [weak self] in self?.readAndAnnounce() }
        // Seeds the deriver with what is already attached, which is why a Mac
        // full of devices announces nothing at launch.
        readAndAnnounce()
    }

    public func stop() {
        emit = nil
        observer.stop()
    }

    private func readAndAnnounce() {
        guard let reading = observer.read() else { return }
        if let payload = deriver.activity(for: reading) {
            emit?(payload)
        }
    }
}

/// The machine's audio devices and its current output, read through CoreAudio.
///
/// Two listeners, one reading. The device list is the only property that fires
/// for a device that has gone away — by then the device itself can no longer be
/// asked anything — and the default-output property is the only one that fires
/// for headphones that never left the list but have taken the sound back.
@MainActor
public final class SystemAudioDeviceObserver: MachineObserving {
    public typealias Reading = AudioDeviceReading

    private static let watched: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultOutputDevice
    ]

    private var listeners: [CoreAudioListener] = []

    public init() {}

    public func read() -> AudioDeviceReading? {
        guard let ids = CoreAudioProperty.values(
            AudioObjectID.self,
            of: CoreAudioProperty.system,
            at: CoreAudioProperty.address(kAudioHardwarePropertyDevices)
        ) else { return nil }

        return AudioDeviceReading(
            devices: ids.compactMap(Self.device(at:)),
            output: Self.name(of: CoreAudioProperty.defaultOutputDevice())
        )
    }

    public func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard listeners.isEmpty else { return }
        listeners = Self.watched.map { selector in
            let listener = CoreAudioListener(
                object: CoreAudioProperty.system,
                address: CoreAudioProperty.address(selector)
            )
            listener.start(onChange)
            return listener
        }
    }

    public func stop() {
        for listener in listeners {
            listener.stop()
        }
        listeners = []
    }

    private static func device(at id: AudioObjectID) -> AudioDevice? {
        guard let name = name(of: id) else { return nil }
        let transport = CoreAudioProperty.value(
            UInt32.self,
            of: id,
            at: CoreAudioProperty.address(kAudioDevicePropertyTransportType)
        )
        return AudioDevice(name: name, transport: Self.transport(transport))
    }

    private static func name(of id: AudioObjectID) -> String? {
        CoreAudioProperty.string(of: id, at: CoreAudioProperty.address(kAudioObjectPropertyName))
    }

    /// CoreAudio's four-character transport codes, reduced to the handful that
    /// change which symbol is drawn. Unknown transports — and a device that does
    /// not report one — fall through to a plain speaker.
    nonisolated static func transport(_ raw: UInt32?) -> AudioTransport {
        switch raw {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        // Classic and LE are the same thing to a listener: wireless headphones.
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: .display
        default: .other
        }
    }
}
