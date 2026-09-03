import CoreAudio
import Foundation
import NotchCore

/// Announces the audio output device by name — which is what makes AirPods say
/// they have connected.
@MainActor
public final class OutputDeviceActivitySource: LiveActivitySource {
    private let observer: any MachineObserving<OutputDeviceReading>
    private var deriver: OutputDeviceActivityDeriver
    private var emit: ((PeekPayload) -> Void)?

    public init(
        observer: any MachineObserving<OutputDeviceReading> = SystemOutputDeviceObserver(),
        deriver: OutputDeviceActivityDeriver = OutputDeviceActivityDeriver()
    ) {
        self.observer = observer
        self.deriver = deriver
    }

    public func start(emit: @escaping (PeekPayload) -> Void) {
        guard self.emit == nil else { return }
        self.emit = emit
        observer.start { [weak self] in self?.readAndAnnounce() }
        // Seeds the deriver with the device already in use, which is why nothing
        // is announced at launch.
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

/// The real default output device, read through CoreAudio.
///
/// The listener is on the *system* object's default-output-device property, so
/// it fires whenever the system re-decides where sound goes. It also fires when
/// nothing the user would notice has changed, which is why the deriver compares
/// names rather than trusting the notification.
@MainActor
public final class SystemOutputDeviceObserver: MachineObserving {
    public typealias Reading = OutputDeviceReading

    private var listener: CoreAudioListener?

    public init() {}

    public func read() -> OutputDeviceReading? {
        let device = CoreAudioProperty.defaultOutputDevice()
        guard device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        guard let name = CoreAudioProperty.string(
            of: device,
            at: CoreAudioProperty.address(kAudioObjectPropertyName)
        ) else { return nil }

        let transport = CoreAudioProperty.value(
            UInt32.self,
            of: device,
            at: CoreAudioProperty.address(kAudioDevicePropertyTransportType)
        )
        return OutputDeviceReading(name: name, transport: Self.transport(transport))
    }

    public func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard listener == nil else { return }
        let listener = CoreAudioListener(
            object: CoreAudioProperty.system,
            address: CoreAudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        )
        listener.start(onChange)
        self.listener = listener
    }

    public func stop() {
        listener?.stop()
        listener = nil
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
