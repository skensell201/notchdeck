import Foundation
import IOKit.ps
import NotchCore
import Support

/// Announces the charger going in and out, and the battery falling low.
@MainActor
public final class PowerActivitySource: LiveActivitySource {
    private let observer: any MachineObserving<PowerReading>
    private var deriver: PowerActivityDeriver
    private var emit: ((PeekPayload) -> Void)?

    public init(
        observer: any MachineObserving<PowerReading> = SystemPowerObserver(),
        deriver: PowerActivityDeriver = PowerActivityDeriver()
    ) {
        self.observer = observer
        self.deriver = deriver
    }

    public func start(emit: @escaping (PeekPayload) -> Void) {
        guard self.emit == nil else { return }
        self.emit = emit
        observer.start { [weak self] in self?.readAndAnnounce() }
        // Seeded immediately so the first real notification has something to be a
        // change from. The deriver never announces on its first reading, so this
        // costs one IOKit read and announces nothing.
        readAndAnnounce()
    }

    public func stop() {
        emit = nil
        observer.stop()
    }

    private func readAndAnnounce() {
        // No battery — a desktop Mac — means nothing to announce, ever.
        guard let reading = observer.read() else { return }
        if let payload = deriver.activity(for: reading) {
            emit?(payload)
        }
    }
}

/// The real power source, read through IOKit.
///
/// `IOPSNotificationCreateRunLoopSource` fires on every change to any power
/// source, which includes the percentage ticking down while nothing interesting
/// is happening. That is fine and intended: the source reads the state and
/// `PowerActivityDeriver` decides whether any of it is news.
@MainActor
public final class SystemPowerObserver: MachineObserving {
    public typealias Reading = PowerReading

    /// Held so the run loop source can be removed again. Retained here rather
    /// than by the run loop alone, which does not hand it back.
    private var runLoopSource: CFRunLoopSource?
    /// A retained reference to self, handed to IOKit as the callback's context.
    ///
    /// Retained rather than unretained on purpose: an observer released without
    /// `stop` would otherwise leave IOKit calling back through a dangling
    /// pointer. Leaking one small object is the better failure.
    private var context: UnsafeMutableRawPointer?
    private var onChange: (@MainActor @Sendable () -> Void)?

    public init() {}

    public func read() -> PowerReading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0
            else { continue }

            // Taken from the battery's own description rather than from
            // `IOPSGetProvidingPowerSourceType`, which is one more copy rule to
            // get wrong for a string this dictionary already carries.
            let state = description[kIOPSPowerSourceStateKey] as? String
            return PowerReading(
                percentage: Double(current) / Double(maximum) * 100,
                isPluggedIn: state == kIOPSACPowerValue
            )
        }
        // A Mac with no internal battery. Not an error, just nothing to say.
        return nil
    }

    public func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard runLoopSource == nil else { return }
        self.onChange = onChange

        let context = Unmanaged.passRetained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let observer = Unmanaged<SystemPowerObserver>.fromOpaque(context).takeUnretainedValue()
            // Added to the main run loop below, so this is the main thread.
            MainActor.assumeIsolated { observer.onChange?() }
        }, context)?.takeRetainedValue() else {
            logger.error("IOPSNotificationCreateRunLoopSource returned nothing")
            Unmanaged<SystemPowerObserver>.fromOpaque(context).release()
            self.onChange = nil
            return
        }

        self.context = context
        runLoopSource = source
        // Common modes rather than the default one: a charger plugged in while a
        // menu is open is still worth announcing.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    public func stop() {
        onChange = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
            self.runLoopSource = nil
        }
        if let context {
            Unmanaged<SystemPowerObserver>.fromOpaque(context).release()
            self.context = nil
        }
    }
}

private let logger = Log.make("live-activities")
