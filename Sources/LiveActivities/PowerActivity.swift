import NotchCore

/// What IOKit says about the power source at one moment.
///
/// Two facts, both of which the user can see for themselves on the menu bar —
/// which is the point: the announcement is about the *change*, and a change
/// needs the previous reading as well. `PowerActivityDeriver` holds that.
public struct PowerReading: Sendable, Equatable {
    /// 0...100, IOKit's own scale.
    public var percentage: Double
    /// Running on mains power. Not the same as charging: a battery at 100% on the
    /// charger reports plugged in and not charging, and the plug is what the user
    /// just did.
    public var isPluggedIn: Bool

    public init(percentage: Double, isPluggedIn: Bool) {
        self.percentage = percentage
        self.isPluggedIn = isPluggedIn
    }
}

/// Turns a stream of power readings into the three announcements worth making.
///
/// The whole difficulty is that IOKit reports *state*, repeatedly — the run-loop
/// notification fires on every percentage change and on plenty of things that
/// are not changes at all — while the notch wants *events*. Everything here
/// exists to turn one into the other without a notch that will not shut up.
public struct PowerActivityDeriver: Sendable {
    /// Below this, on battery, is worth interrupting the user for. Matches the
    /// level at which macOS itself starts warning.
    public static let lowBatteryThreshold: Double = 20
    /// The battery must climb this far back above the threshold before a second
    /// warning is possible. Without the margin, a charge hovering on the boundary
    /// — which is exactly what happens when a nearly-flat machine is plugged in
    /// and unplugged, or when the estimate wobbles by a point — would re-arm and
    /// re-fire indefinitely.
    public static let rearmMargin: Double = 5

    /// Long enough to read a couple of words. Longer than a volume peek, which
    /// the user is actively driving and does not need to read.
    public static let duration: Duration = .seconds(3)

    private let threshold: Double
    private let rearmLevel: Double

    /// The reading the next one is compared against. Nil before the first, which
    /// is why a launch announces nothing: at launch nothing has changed, it is
    /// merely the first time we looked.
    private var previous: PowerReading?
    /// Whether a low-battery warning is still owed. Cleared when one is given,
    /// set again only once the charge climbs back past `rearmLevel`.
    private var lowWarningArmed = false

    public init(
        threshold: Double = PowerActivityDeriver.lowBatteryThreshold,
        rearmMargin: Double = PowerActivityDeriver.rearmMargin
    ) {
        self.threshold = threshold
        self.rearmLevel = threshold + rearmMargin
    }

    public mutating func activity(for reading: PowerReading) -> PeekPayload? {
        defer { previous = reading }

        // Re-arming happens whatever else is going on, including on the very
        // first reading: a machine that starts at 80% has its warning ready, and
        // one that starts at 15% does not get a warning for a discharge that
        // began before we were watching.
        if reading.percentage >= rearmLevel {
            lowWarningArmed = true
        }

        guard let previous else {
            // The first reading is a baseline, not an event.
            return nil
        }

        if previous.isPluggedIn != reading.isPluggedIn {
            // The plug wins over a low warning: the user has just fixed the
            // problem the warning would be about, or just caused it, and either
            // way the plug is the news. The warning stays armed and will fire on
            // the next reading below the threshold.
            return Self.plugPayload(reading)
        }

        if lowWarningArmed, !reading.isPluggedIn, reading.percentage < threshold {
            lowWarningArmed = false
            return Self.lowPayload(reading)
        }

        // A percentage that merely ticked down is not news.
        return nil
    }

    // MARK: Payloads

    /// Stable across all three kinds, so a low-battery warning replaces a
    /// just-unplugged announcement rather than queueing behind it.
    static let id = "power"

    static func plugPayload(_ reading: PowerReading) -> PeekPayload {
        PeekPayload(
            id: id,
            duration: duration,
            symbolName: reading.isPluggedIn ? "powerplug.fill" : "battery.50",
            title: reading.isPluggedIn ? "Charging" : "On Battery",
            // The level bar carries the percentage; the shell hides `detail`
            // whenever a level is present, so putting the number in both would
            // only show it in one.
            level: level(reading)
        )
    }

    static func lowPayload(_ reading: PowerReading) -> PeekPayload {
        PeekPayload(
            id: id,
            duration: duration,
            symbolName: "battery.25",
            title: "Low Battery",
            level: level(reading)
        )
    }

    private static func level(_ reading: PowerReading) -> Double {
        min(max(reading.percentage / 100, 0), 1)
    }
}
