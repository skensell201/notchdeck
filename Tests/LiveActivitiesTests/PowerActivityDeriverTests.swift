import Testing
@testable import LiveActivities

@Suite("Power activities")
struct PowerActivityDeriverTests {
    private func reading(_ percentage: Double, pluggedIn: Bool = false) -> PowerReading {
        PowerReading(percentage: percentage, isPluggedIn: pluggedIn)
    }

    // MARK: The baseline

    @Test("the first reading announces nothing, because nothing has changed yet")
    func firstReadingIsABaseline() {
        var deriver = PowerActivityDeriver()

        // Launching on the charger is not the same as plugging one in.
        #expect(deriver.activity(for: reading(80, pluggedIn: true)) == nil)
    }

    @Test("a percentage that merely ticks down announces nothing")
    func percentageTicksAreNotNews() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(80))

        #expect(deriver.activity(for: reading(79)) == nil)
        #expect(deriver.activity(for: reading(78)) == nil)
    }

    @Test("an identical reading announces nothing, however often IOKit repeats it")
    func repeatedReadingsAreNotNews() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(80))

        for _ in 0..<10 {
            #expect(deriver.activity(for: reading(80)) == nil)
        }
    }

    // MARK: The charger

    @Test("plugging in announces charging, with the charge as the level")
    func pluggingIn() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(62))

        let payload = deriver.activity(for: reading(62, pluggedIn: true))

        #expect(payload?.title == "Charging")
        #expect(payload?.symbolName == "powerplug.fill")
        #expect(payload?.level == 0.62)
        #expect(payload?.id == "power")
    }

    @Test("unplugging announces running on battery")
    func unplugging() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(62, pluggedIn: true))

        let payload = deriver.activity(for: reading(62))

        #expect(payload?.title == "On Battery")
        #expect(payload?.symbolName == "battery.50")
        #expect(payload?.level == 0.62)
    }

    @Test("staying on the charger announces nothing more")
    func stayingPluggedIn() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(62))
        _ = deriver.activity(for: reading(62, pluggedIn: true))

        #expect(deriver.activity(for: reading(63, pluggedIn: true)) == nil)
        #expect(deriver.activity(for: reading(64, pluggedIn: true)) == nil)
    }

    // MARK: The low-battery threshold

    @Test("crossing the threshold on battery warns once, not on every reading below it")
    func lowBatteryWarnsOnce() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(40))

        let warning = deriver.activity(for: reading(19))

        #expect(warning?.title == "Low Battery")
        #expect(warning?.symbolName == "battery.25")
        #expect(warning?.level == 0.19)
        // The notch that will not shut up: IOKit keeps reporting 19%, then 18%,
        // then 18% again, and none of those is a new thing to say.
        #expect(deriver.activity(for: reading(19)) == nil)
        #expect(deriver.activity(for: reading(18)) == nil)
        #expect(deriver.activity(for: reading(17)) == nil)
        #expect(deriver.activity(for: reading(1)) == nil)
    }

    @Test("the warning re-arms once the battery has charged back above the threshold")
    func lowBatteryRearms() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(40))
        #expect(deriver.activity(for: reading(19)) != nil)

        // Charged, unplugged, and run down again: a second session deserves a
        // second warning.
        _ = deriver.activity(for: reading(19, pluggedIn: true))
        _ = deriver.activity(for: reading(60, pluggedIn: true))
        _ = deriver.activity(for: reading(60))

        #expect(deriver.activity(for: reading(19))?.title == "Low Battery")
    }

    @Test("a charge hovering just above the threshold does not re-arm the warning")
    func hoveringDoesNotRearm() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(40))
        #expect(deriver.activity(for: reading(19)) != nil)

        // A percentage wobbling by a point either side of the boundary — which is
        // what a nearly-flat battery does — must not produce a warning per wobble.
        for _ in 0..<5 {
            _ = deriver.activity(for: reading(20))
            #expect(deriver.activity(for: reading(19)) == nil)
        }
    }

    @Test("a battery already low when the app launches is not warned about")
    func alreadyLowAtLaunch() {
        var deriver = PowerActivityDeriver()

        // The discharge began before anyone was watching; announcing it now would
        // be announcing the app starting, not the battery falling.
        #expect(deriver.activity(for: reading(15)) == nil)
        #expect(deriver.activity(for: reading(14)) == nil)
    }

    @Test("a low battery on the charger is not a warning")
    func lowWhileChargingIsNotAWarning() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(40))
        _ = deriver.activity(for: reading(40, pluggedIn: true))

        // 12% and rising is the problem solving itself.
        #expect(deriver.activity(for: reading(12, pluggedIn: true)) == nil)
    }

    @Test("unplugging below the threshold announces the plug first, then warns")
    func unpluggingBelowTheThreshold() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(40))
        _ = deriver.activity(for: reading(40, pluggedIn: true))

        // Charged past the re-arm level, then pulled out while still low.
        _ = deriver.activity(for: reading(30, pluggedIn: true))
        #expect(deriver.activity(for: reading(15))?.title == "On Battery")
        // The plug was the news that reading; the warning is the news the next.
        #expect(deriver.activity(for: reading(15))?.title == "Low Battery")
    }

    @Test("every power announcement shares one identity, so the later replaces the earlier")
    func oneIdentity() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(40))
        let unplugged = deriver.activity(for: reading(40, pluggedIn: true))
        let warning = {
            var deriver = PowerActivityDeriver()
            _ = deriver.activity(for: reading(40))
            return deriver.activity(for: reading(10))
        }()

        #expect(unplugged?.id == "power")
        #expect(warning?.id == "power")
    }

    @Test("a percentage outside 0-100 is clamped rather than drawn as a bar off the end")
    func levelIsClamped() {
        var deriver = PowerActivityDeriver()
        _ = deriver.activity(for: reading(50))

        #expect(deriver.activity(for: reading(140, pluggedIn: true))?.level == 1)
    }
}
