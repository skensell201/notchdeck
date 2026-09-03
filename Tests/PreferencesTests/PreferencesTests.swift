import Foundation
import NotchCore
import Testing
@testable import Preferences

@MainActor
@Suite("Preferences")
struct PreferencesTests {
    private func makePreferences() -> Preferences {
        let suite = UserDefaults(suiteName: "notchdeck.tests.\(UUID().uuidString)")!
        return Preferences(defaults: suite)
    }

    @Test("every default matches the constant it replaced, so an untouched install is unchanged")
    func defaultsMatchTheOldConstants() {
        let preferences = makePreferences()

        #expect(preferences.syntheticNotchSize == CGSize(width: 220, height: 32))
        #expect(preferences.hoverDwellMilliseconds == 180)
        #expect(preferences.exitGraceMilliseconds == 220)
        #expect(preferences.clipboardCapacity == 60)
        #expect(!preferences.suppressVolumeHUD)
        #expect(!preferences.dismissWithEscape)
        #expect(preferences.clipboardExclusions.isEmpty)
        #expect(preferences.moduleLayout == ModuleLayout())
    }

    @Test("a module layout survives a round trip, including a module this build does not know")
    func layoutRoundTrip() {
        let preferences = makePreferences()
        let layout = ModuleLayout(
            order: [ModuleID("media"), ModuleID("from-the-future"), ModuleID("shelf")],
            disabled: [ModuleID("shelf")]
        )

        preferences.moduleLayout = layout

        #expect(preferences.moduleLayout == layout)
    }

    @Test("an unreadable stored layout falls back to empty rather than crashing")
    func corruptLayoutIsDiscarded() {
        let suite = UserDefaults(suiteName: "notchdeck.tests.\(UUID().uuidString)")!
        suite.set(Data([0x00, 0x01]), forKey: Preferences.Key.moduleLayout)
        let preferences = Preferences(defaults: suite)

        #expect(preferences.moduleLayout == ModuleLayout())
    }

    @Test("a synthetic notch cannot be set to something unusable")
    func syntheticSizeIsClamped() {
        let preferences = makePreferences()

        preferences.syntheticNotchSize = CGSize(width: 5, height: 2)
        #expect(preferences.syntheticNotchSize == CGSize(width: 120, height: 20))

        preferences.syntheticNotchSize = CGSize(width: 9000, height: 900)
        #expect(preferences.syntheticNotchSize == CGSize(width: 600, height: 60))
    }

    @Test("a hover dwell of zero would open the notch on any pointer crossing it")
    func dwellIsClamped() {
        let preferences = makePreferences()

        preferences.hoverDwellMilliseconds = 0
        #expect(preferences.hoverDwellMilliseconds == 60)

        preferences.hoverDwellMilliseconds = 99_999
        #expect(preferences.hoverDwellMilliseconds == 1000)
    }

    @Test("the exit grace may legitimately be zero, but not absurd")
    func graceIsClamped() {
        let preferences = makePreferences()

        preferences.exitGraceMilliseconds = 0
        #expect(preferences.exitGraceMilliseconds == 0)

        preferences.exitGraceMilliseconds = 99_999
        #expect(preferences.exitGraceMilliseconds == 2000)
    }

    @Test("clipboard capacity is clamped to something a panel can show and a disk can hold")
    func capacityIsClamped() {
        let preferences = makePreferences()

        preferences.clipboardCapacity = 1
        #expect(preferences.clipboardCapacity == 5)

        preferences.clipboardCapacity = 100_000
        #expect(preferences.clipboardCapacity == 500)
    }

    @Test("timings are derived from the stored milliseconds")
    func timingIsDerived() {
        let preferences = makePreferences()
        preferences.hoverDwellMilliseconds = 250
        preferences.exitGraceMilliseconds = 400

        #expect(preferences.timing == NotchTiming(hoverDwell: .milliseconds(250), exitGrace: .milliseconds(400)))
    }

    @Test("exclusions round-trip")
    func exclusionsRoundTrip() {
        let preferences = makePreferences()

        preferences.clipboardExclusions = ["com.agilebits.onepassword7", "com.apple.keychainaccess"]

        #expect(preferences.clipboardExclusions.count == 2)
    }
}
