import AppKit

public enum TransportAction: Equatable, Sendable {
    case play, pause, toggle, next, previous

    /// The adapter's `send` command id.
    var adapterCommandID: Int {
        switch self {
        case .play: 0
        case .pause: 1
        case .toggle: 2
        case .next: 4
        case .previous: 5
        }
    }

    /// The `NX_KEYTYPE_*` code for the fallback. Play, pause and toggle all share
    /// the play key, which is itself a toggle.
    var mediaKeyCode: Int32 {
        switch self {
        case .play, .pause, .toggle: 16
        case .next: 17
        case .previous: 18
        }
    }
}

/// Runs a one-shot adapter command, reporting whether it exited cleanly.
public protocol AdapterCommandRunner: Sendable {
    func run(arguments: [String]) async -> Bool
}

/// Posts a system-defined media key event.
public protocol MediaKeyPoster: Sendable {
    func post(keyCode: Int32)
}

public struct MediaCommands: Sendable {
    private let adapter: (any AdapterCommandRunner)?
    private let keys: any MediaKeyPoster

    public init(adapter: (any AdapterCommandRunner)?, keys: any MediaKeyPoster) {
        self.adapter = adapter
        self.keys = keys
    }

    public func perform(_ action: TransportAction) async {
        if let adapter, await adapter.run(arguments: ["send", String(action.adapterCommandID)]) {
            return
        }
        keys.post(keyCode: action.mediaKeyCode)
    }

    /// Seeking has no media-key equivalent, so a missing or failing adapter is
    /// simply a failure the caller has to show.
    public func seek(toMicros micros: Int64) async -> Bool {
        guard let adapter else { return false }
        return await adapter.run(arguments: ["seek", String(micros)])
    }
}

/// Posts `NX_KEYTYPE_*` events through the HID event tap.
///
/// Note: synthesising input may require Accessibility permission on macOS 26. This
/// is only the fallback path — the adapter needs no permission at all — so a
/// failure here degrades transport rather than breaking the module. Verify the
/// behaviour by hand and record the result in the README checklist.
public struct SystemMediaKeyPoster: MediaKeyPoster {
    public init() {}

    public func post(keyCode: Int32) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(isDown ? 0xA00 : 0xB00))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((keyCode << 16)) | Int(isDown ? 0xA00 : 0xB00),
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
