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
        // The notch keeps its own shape until the user asks for the wide band.
        #expect(!preferences.showLiveContentWhenClosed)
        #expect(preferences.clipboardExclusions.isEmpty)
        #expect(preferences.moduleLayout == ModuleLayout())
    }

    @Test("the collapsed band setting survives a round trip")
    func liveContentRoundTrip() {
        let preferences = makePreferences()

        preferences.showLiveContentWhenClosed = true

        #expect(preferences.showLiveContentWhenClosed)
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

    @Test("a fresh install has no panel tint, so the notch stays the flat black it was")
    func tintIsOffByDefault() {
        let preferences = makePreferences()

        #expect(preferences.notchTint == nil)
        #expect(preferences.notchTintStrength == 0.7)
    }

    @Test("a tint survives a round trip through defaults")
    func tintRoundTrip() {
        let suite = UserDefaults(suiteName: "notchdeck.tests.\(UUID().uuidString)")!
        let first = Preferences(defaults: suite)
        let indigo = NotchTint(red: 0.169, green: 0.239, blue: 0.471)

        first.notchTint = indigo
        first.notchTintStrength = 0.55

        let second = Preferences(defaults: suite)

        #expect(second.notchTint == indigo)
        #expect(second.notchTintStrength == 0.55)
    }

    @Test("clearing the tint puts the panel back to black rather than leaving a stale colour")
    func tintCanBeCleared() {
        let suite = UserDefaults(suiteName: "notchdeck.tests.\(UUID().uuidString)")!
        let first = Preferences(defaults: suite)
        first.notchTint = NotchTint(red: 0.5, green: 0.2, blue: 0.1)

        first.notchTint = nil

        #expect(first.notchTint == nil)
        #expect(Preferences(defaults: suite).notchTint == nil)
    }

    @Test("a strength outside the range is clamped, not stored as written")
    func tintStrengthIsClamped() {
        let preferences = makePreferences()

        preferences.notchTintStrength = 4
        #expect(preferences.notchTintStrength == 1)

        preferences.notchTintStrength = -2
        #expect(preferences.notchTintStrength == 0)
    }
}

/// `withObservationTracking`'s onChange runs off the main actor, so the flag it
/// sets cannot be a captured local.
private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func mark() { lock.withLock { value = true } }
    var wasNotified: Bool { lock.withLock { value } }
}

@MainActor
@Suite("Preferences observation")
struct PreferencesObservationTests {
    /// The bug this guards: the values used to be computed straight over
    /// `UserDefaults`, which `@Observable` cannot instrument, so a slider bound to
    /// one moved, wrote, and never saw its own label update.
    @Test("changing a value notifies an observer")
    func writingNotifies() async {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "notchdeck.tests.\(UUID().uuidString)")!)
        let notified = ChangeFlag()

        withObservationTracking {
            _ = preferences.hoverDwellMilliseconds
        } onChange: {
            notified.mark()
        }

        preferences.hoverDwellMilliseconds = 400
        await Task.yield()

        #expect(notified.wasNotified)
    }

    @Test("a clamped write still notifies, so the control snaps back visibly")
    func clampedWriteNotifies() async {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "notchdeck.tests.\(UUID().uuidString)")!)
        let notified = ChangeFlag()

        withObservationTracking {
            _ = preferences.syntheticNotchSize
        } onChange: {
            notified.mark()
        }

        preferences.syntheticNotchSize = CGSize(width: 9000, height: 900)
        await Task.yield()

        #expect(notified.wasNotified)
        #expect(preferences.syntheticNotchSize.width == 600)
    }

    @Test("values written by one instance are read by the next, so they outlive a launch")
    func valuesPersistAcrossInstances() {
        let suite = UserDefaults(suiteName: "notchdeck.tests.\(UUID().uuidString)")!
        let first = Preferences(defaults: suite)

        first.hoverDwellMilliseconds = 320
        first.exitGraceMilliseconds = 90
        first.syntheticNotchSize = CGSize(width: 300, height: 40)
        first.suppressVolumeHUD = true
        first.clipboardCapacity = 25

        let second = Preferences(defaults: suite)

        #expect(second.hoverDwellMilliseconds == 320)
        #expect(second.exitGraceMilliseconds == 90)
        #expect(second.syntheticNotchSize == CGSize(width: 300, height: 40))
        #expect(second.suppressVolumeHUD)
        #expect(second.clipboardCapacity == 25)
    }
}
