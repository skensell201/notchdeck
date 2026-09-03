import AudioToolbox
import CoreAudio
import Foundation
import NotchCore

/// Announces the output volume, and mute as a state of its own.
@MainActor
public final class VolumeActivitySource: LiveActivitySource {
    private let observer: any MachineObserving<VolumeReading>
    private var deriver: VolumeActivityDeriver
    private var emit: ((PeekPayload) -> Void)?

    public init(
        observer: any MachineObserving<VolumeReading> = SystemVolumeObserver(),
        deriver: VolumeActivityDeriver = VolumeActivityDeriver()
    ) {
        self.observer = observer
        self.deriver = deriver
    }

    public func start(emit: @escaping (PeekPayload) -> Void) {
        guard self.emit == nil else { return }
        self.emit = emit
        observer.start { [weak self] in self?.readAndAnnounce() }
        // Seeds the deriver with whatever the volume already is, so the notch
        // does not announce the current volume at launch.
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

/// The real volume, read through CoreAudio.
///
/// Two things make this more than one listener. The volume and the mute switch
/// are separate properties, and both matter; and both live on the *current*
/// default output device, which changes when headphones arrive — so the
/// listeners have to move with it, which is what the third listener is for.
@MainActor
public final class SystemVolumeObserver: MachineObserving {
    public typealias Reading = VolumeReading

    private static let volumeAddress = CoreAudioProperty.address(
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        scope: kAudioDevicePropertyScopeOutput
    )
    private static let muteAddress = CoreAudioProperty.address(
        kAudioDevicePropertyMute,
        scope: kAudioDevicePropertyScopeOutput
    )

    private var deviceListener: CoreAudioListener?
    /// The listeners on whichever device is currently the default. Replaced
    /// wholesale when it changes: a listener is bound to the object it was
    /// registered against, so there is nothing to re-point.
    private var deviceListeners: [CoreAudioListener] = []
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var onChange: (@MainActor @Sendable () -> Void)?

    public init() {}

    public func read() -> VolumeReading? {
        // Read fresh rather than from `device`: a notification about the default
        // device changing and a read of the volume must not disagree about which
        // device they mean.
        let device = CoreAudioProperty.defaultOutputDevice()
        guard device != AudioObjectID(kAudioObjectUnknown) else { return nil }

        let level = CoreAudioProperty
            .value(Float32.self, of: device, at: Self.volumeAddress)
            .map { Double($0) }
        // A device with no mute property is not muted; it simply cannot be.
        let muted = CoreAudioProperty
            .value(UInt32.self, of: device, at: Self.muteAddress)
            .map { $0 != 0 } ?? false

        guard level != nil || muted else {
            // Nothing readable and nothing muted: an HDMI display, say. Reporting
            // a reading of "no level, not muted" would be indistinguishable from
            // a real one, so report nothing at all.
            return nil
        }
        return VolumeReading(level: level, isMuted: muted)
    }

    public func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard deviceListener == nil else { return }
        self.onChange = onChange

        let listener = CoreAudioListener(
            object: CoreAudioProperty.system,
            address: CoreAudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        )
        listener.start { [weak self] in self?.defaultDeviceChanged() }
        deviceListener = listener

        attachToDefaultDevice()
    }

    public func stop() {
        onChange = nil
        deviceListener?.stop()
        deviceListener = nil
        detachFromDevice()
    }

    // MARK: Following the default device

    private func defaultDeviceChanged() {
        attachToDefaultDevice()
        // The new device has its own volume and its own mute switch, and the user
        // is about to be told which device it is by the other source. Reporting
        // the new level here as well would be two announcements for one act, so
        // the deriver's unchanged-reading rule quietly drops it when the level
        // happens to match.
        onChange?()
    }

    private func attachToDefaultDevice() {
        let device = CoreAudioProperty.defaultOutputDevice()
        guard device != self.device else { return }
        detachFromDevice()
        self.device = device
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }

        for address in [Self.volumeAddress, Self.muteAddress] {
            let listener = CoreAudioListener(object: device, address: address)
            // A device without the property refuses the listener, which is
            // expected rather than an error: it simply never fires.
            if listener.start({ [weak self] in self?.onChange?() }) {
                deviceListeners.append(listener)
            }
        }
    }

    private func detachFromDevice() {
        for listener in deviceListeners {
            listener.stop()
        }
        deviceListeners.removeAll()
        device = AudioObjectID(kAudioObjectUnknown)
    }
}
