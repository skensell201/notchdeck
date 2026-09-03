import Testing
@testable import LiveActivities

@Suite("Volume activities")
struct VolumeActivityDeriverTests {
    private func reading(_ level: Double?, muted: Bool = false) -> VolumeReading {
        VolumeReading(level: level, isMuted: muted)
    }

    // MARK: The baseline

    @Test("the volume the app launches at is not announced")
    func firstReadingIsABaseline() {
        var deriver = VolumeActivityDeriver()

        #expect(deriver.activity(for: reading(0.4)) == nil)
    }

    @Test("a change announces the new level")
    func changeAnnouncesTheLevel() {
        var deriver = VolumeActivityDeriver()
        _ = deriver.activity(for: reading(0.4))

        let payload = deriver.activity(for: reading(0.5))

        #expect(payload?.id == "volume")
        #expect(payload?.title == "Volume")
        #expect(payload?.level == 0.5)
    }

    @Test("the same reading twice announces once")
    func duplicateNotificationsAnnounceOnce() {
        // Not hypothetical: on this machine CoreAudio fires the virtual main
        // volume listener twice for every single change, with the same value both
        // times. The second one would restart the peek's timeout for nothing.
        var deriver = VolumeActivityDeriver()
        _ = deriver.activity(for: reading(0.4))

        #expect(deriver.activity(for: reading(0.5)) != nil)
        #expect(deriver.activity(for: reading(0.5)) == nil)
        #expect(deriver.activity(for: reading(0.5)) == nil)
    }

    @Test("a level changed and then changed back announces both times")
    func returningToAPreviousLevelStillAnnounces() {
        var deriver = VolumeActivityDeriver()
        _ = deriver.activity(for: reading(0.4))

        #expect(deriver.activity(for: reading(0.5)) != nil)
        // Only the immediately preceding reading is a duplicate. Going back down
        // is a thing the user just did.
        #expect(deriver.activity(for: reading(0.4)) != nil)
    }

    // MARK: Mute

    @Test("muting shows its own symbol and no level at all")
    func muteIsNotAZeroLevel() {
        var deriver = VolumeActivityDeriver()
        _ = deriver.activity(for: reading(0.6))

        let payload = deriver.activity(for: reading(0.6, muted: true))

        #expect(payload?.symbolName == "speaker.slash.fill")
        #expect(payload?.title == "Muted")
        // A muted device still remembers the slider at 0.6. Drawing that as a bar
        // would say the sound is on; drawing zero would say the slider moved.
        #expect(payload?.level == nil)
    }

    @Test("unmuting announces the level the device was left at")
    func unmutingAnnouncesTheLevel() {
        var deriver = VolumeActivityDeriver()
        _ = deriver.activity(for: reading(0.6, muted: true))

        let payload = deriver.activity(for: reading(0.6))

        #expect(payload?.title == "Volume")
        #expect(payload?.level == 0.6)
    }

    @Test("changing the level while muted stays muted")
    func levelChangesWhileMutedStayMuted() {
        var deriver = VolumeActivityDeriver()
        _ = deriver.activity(for: reading(0.6, muted: true))

        #expect(deriver.activity(for: reading(0.3, muted: true))?.title == "Muted")
    }

    // MARK: Devices with no volume control

    @Test("a device with no volume control and no mute announces nothing")
    func noVolumeControlAnnouncesNothing() {
        // HDMI and some aggregate devices: there is no level to draw, and nothing
        // the user could have done to produce one.
        var deriver = VolumeActivityDeriver()
        _ = deriver.activity(for: reading(0.5))

        #expect(deriver.activity(for: reading(nil)) == nil)
    }

    @Test("a device with no volume control can still be muted")
    func mutedWithoutAVolumeControl() {
        var deriver = VolumeActivityDeriver()
        _ = deriver.activity(for: reading(nil))

        #expect(deriver.activity(for: reading(nil, muted: true))?.title == "Muted")
    }

    // MARK: The symbol

    @Test("the speaker's waves fill up as the level rises, as they do in the system overlay")
    func symbolFollowsTheLevel() {
        #expect(VolumeActivityDeriver.symbolName(for: 0) == "speaker.fill")
        #expect(VolumeActivityDeriver.symbolName(for: 0.1) == "speaker.wave.1.fill")
        #expect(VolumeActivityDeriver.symbolName(for: 0.5) == "speaker.wave.2.fill")
        #expect(VolumeActivityDeriver.symbolName(for: 1) == "speaker.wave.3.fill")
    }

    @Test("a level outside 0-1 is clamped rather than drawn as a bar off the end")
    func levelIsClamped() {
        #expect(VolumeActivityDeriver.payload(for: reading(1.4))?.level == 1)
        #expect(VolumeActivityDeriver.payload(for: reading(-0.2))?.level == 0)
    }
}
