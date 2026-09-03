import CoreAudio
import Foundation
import Support

/// One registered CoreAudio property listener, remembered well enough to be
/// removed again.
///
/// CoreAudio takes the block by value and hands nothing back, so removing a
/// listener means presenting the very same block and address that were
/// registered. Keeping the pair together in one object is what makes `stop`
/// possible at all.
///
/// Unregistering deliberately does not happen in `deinit`: it needs the main
/// actor, and a `deinit` has no business hopping actors. The owning observer's
/// `stop` unregisters, and `LiveActivityCenter.stop` is what calls that.
@MainActor
final class CoreAudioListener {
    private let object: AudioObjectID
    private let address: AudioObjectPropertyAddress
    /// Non-nil exactly while registered, so it doubles as the "am I on?" flag.
    private var block: AudioObjectPropertyListenerBlock?

    init(object: AudioObjectID, address: AudioObjectPropertyAddress) {
        self.object = object
        self.address = address
    }

    /// - Returns: whether the listener was registered. False for a device that
    ///   has gone away between being chosen and being listened to, which is
    ///   ordinary on a machine where headphones come and go.
    @discardableResult
    func start(_ handler: @escaping @MainActor @Sendable () -> Void) -> Bool {
        guard block == nil, object != AudioObjectID(kAudioObjectUnknown) else { return false }

        let block: AudioObjectPropertyListenerBlock = { _, _ in
            // Registered against `DispatchQueue.main` below, so this genuinely is
            // the main thread and the assertion is free. A `Task` hop instead
            // would reorder notifications against each other and against the
            // reads they trigger.
            MainActor.assumeIsolated { handler() }
        }
        var address = self.address
        let status = AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block)
        guard status == noErr else {
            logger.error("AudioObjectAddPropertyListenerBlock failed: \(status, privacy: .public)")
            return false
        }
        self.block = block
        return true
    }

    func stop() {
        guard let block else { return }
        self.block = nil
        var address = self.address
        let status = AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        if status != noErr {
            // Worth a line, not a crash: the usual cause is the device having
            // been removed already, which takes its listeners with it.
            logger.debug("AudioObjectRemovePropertyListenerBlock failed: \(status, privacy: .public)")
        }
    }
}

private let logger = Log.make("live-activities")
