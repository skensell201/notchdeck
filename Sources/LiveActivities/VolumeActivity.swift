import NotchCore

/// The output volume at one moment.
public struct VolumeReading: Sendable, Equatable {
    /// 0...1, CoreAudio's own scale for the virtual main volume. Nil when the
    /// current output device exposes no volume control at all, which is normal
    /// for HDMI and for some aggregate devices.
    public var level: Double?
    /// Independent of the level: a muted device still remembers where the slider
    /// was, and reports it. Showing that as a zero level would be a lie, which is
    /// why mute is a symbol of its own.
    public var isMuted: Bool

    public init(level: Double?, isMuted: Bool) {
        self.level = level.map { min(max($0, 0), 1) }
        self.isMuted = isMuted
    }
}

/// Turns volume readings into peeks, and — more importantly — decides which ones
/// are not worth a peek at all.
public struct VolumeActivityDeriver: Sendable {
    /// Short: the user is driving this one, and each press replaces the last, so
    /// the peek lasts a moment past the final press rather than sitting there.
    public static let duration: Duration = .milliseconds(1200)

    static let id = "volume"

    /// The last reading seen. Compared against, because the CoreAudio listener
    /// genuinely fires twice for a single volume change on this machine — same
    /// property, same value, two callbacks — and unrelated property churn
    /// produces more of the same. Announcing those would restart the peek's
    /// timeout and leave the notch open for no reason.
    ///
    /// Nil before the first reading, which is why the volume the app happens to
    /// launch at is never announced: that is not a change, it is the first look.
    private var previous: VolumeReading?

    public init() {}

    public mutating func activity(for reading: VolumeReading) -> PeekPayload? {
        let last = previous
        previous = reading
        guard let last else { return nil }
        guard reading != last else { return nil }
        return Self.payload(for: reading)
    }

    /// The payload a reading would produce, ignoring what came before it.
    ///
    /// Nil for an unmuted device with no volume control: there is no level to
    /// draw and nothing the user could have just done to it.
    public static func payload(for reading: VolumeReading) -> PeekPayload? {
        if reading.isMuted {
            return PeekPayload(
                id: id,
                duration: duration,
                symbolName: "speaker.slash.fill",
                title: "Muted"
            )
        }
        guard let level = reading.level else { return nil }
        return PeekPayload(
            id: id,
            duration: duration,
            symbolName: symbolName(for: level),
            title: "Volume",
            level: level
        )
    }

    /// The waves fill up as the level rises, matching what macOS draws in its own
    /// overlay — which this is meant to replace, so it should not look different.
    static func symbolName(for level: Double) -> String {
        switch level {
        case ..<0.001: "speaker.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
