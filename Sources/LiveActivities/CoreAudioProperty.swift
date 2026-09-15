import CoreAudio
import Foundation

/// The small amount of CoreAudio boilerplate the two audio observers share.
///
/// `AudioObjectGetPropertyData` is four out-parameters and a status code around
/// what is really "read this value". Wrapping it once keeps the observers about
/// the thing they observe, and keeps the pointer handling — the part that would
/// be wrong in the same way in three places — in one place.
enum CoreAudioProperty {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Reads a fixed-size C value — an `AudioObjectID`, a `Float32`, a
    /// `UInt32` flag. Nil when the object does not have the property at all,
    /// which is a normal answer: not every device has a volume control.
    ///
    /// Only for trivially copyable types. Anything reference-counted comes back
    /// with a retain the caller owns, so it needs `string(...)` below instead.
    static func value<Value>(
        _ type: Value.Type = Value.self,
        of object: AudioObjectID,
        at address: AudioObjectPropertyAddress
    ) -> Value? {
        var address = address
        guard object != AudioObjectID(kAudioObjectUnknown),
              AudioObjectHasProperty(object, &address)
        else { return nil }

        var size = UInt32(MemoryLayout<Value>.size)
        return withUnsafeTemporaryAllocation(of: Value.self, capacity: 1) { buffer -> Value? in
            guard let pointer = buffer.baseAddress else { return nil }
            let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
            // The buffer is uninitialised until the call fills it, so nothing may
            // read it — not even to destroy it — unless the call succeeded.
            guard status == noErr, size == UInt32(MemoryLayout<Value>.size) else { return nil }
            return pointer.pointee
        }
    }

    /// Reads a variable-length array property, such as the list of every audio
    /// device the machine has. Nil rather than an empty array when the read
    /// fails: "no devices at all" and "the question could not be asked" mean
    /// opposite things to anything watching for devices to disappear.
    static func values<Value>(
        _ type: Value.Type = Value.self,
        of object: AudioObjectID,
        at address: AudioObjectPropertyAddress
    ) -> [Value]? {
        var address = address
        guard object != AudioObjectID(kAudioObjectUnknown),
              AudioObjectHasProperty(object, &address)
        else { return nil }

        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        let capacity = Int(size) / MemoryLayout<Value>.stride
        guard capacity > 0 else { return [] }

        return withUnsafeTemporaryAllocation(of: Value.self, capacity: capacity) { buffer -> [Value]? in
            guard let pointer = buffer.baseAddress else { return nil }
            var size = size
            let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
            guard status == noErr else { return nil }
            return Array(UnsafeBufferPointer(start: pointer, count: Int(size) / MemoryLayout<Value>.stride))
        }
    }

    /// Reads a `CFString` property, such as a device's name.
    ///
    /// The HAL hands these back with a retain the caller owns, despite the
    /// property being spelled as a get — hence `takeRetainedValue`.
    static func string(of object: AudioObjectID, at address: AudioObjectPropertyAddress) -> String? {
        var address = address
        guard object != AudioObjectID(kAudioObjectUnknown),
              AudioObjectHasProperty(object, &address)
        else { return nil }

        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// The device the system is currently playing through, or
    /// `kAudioObjectUnknown` when there is none — which happens for real, on a
    /// machine whose only output has just been unplugged.
    static func defaultOutputDevice() -> AudioObjectID {
        value(AudioObjectID.self, of: system, at: address(kAudioHardwarePropertyDefaultOutputDevice))
            ?? AudioObjectID(kAudioObjectUnknown)
    }
}
