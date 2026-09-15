import NotchCore
import Testing
@testable import SettingsUI

private func builtIn(_ name: String = "Color LCD") -> DisplayNotch {
    DisplayNotch(name: name, kind: .physical)
}

private func external(_ name: String = "Studio Display") -> DisplayNotch {
    DisplayNotch(name: name, kind: .synthetic)
}

@Suite("Synthetic notch note")
struct SyntheticNotchNoteTests {
    @Test("says nothing when no display can be read")
    func silentWithoutDisplays() {
        #expect(SyntheticNotchNote.text(for: []) == nil)
    }

    @Test("explains the silence when the only display has its own notch")
    func onlyPhysical() {
        #expect(
            SyntheticNotchNote.text(for: [builtIn()])
                == "Color LCD has a notch of its own, so nothing here applies right now."
        )
    }

    @Test("uses the plural when several displays have their own notch")
    func severalPhysical() {
        #expect(
            SyntheticNotchNote.text(for: [builtIn(), builtIn("Sidecar")])
                == "Color LCD and Sidecar have notches of their own, so nothing here applies right now."
        )
    }

    @Test("names the displays the numbers are drawn on")
    func onlySynthetic() {
        #expect(SyntheticNotchNote.text(for: [external()]) == "In use on Studio Display.")
    }

    @Test("separates the displays that use the numbers from the one that ignores them")
    func mixed() {
        #expect(
            SyntheticNotchNote.text(for: [builtIn(), external()])
                == "In use on Studio Display. Color LCD has a notch of its own and ignores these numbers."
        )
    }

    @Test("lists three displays with the last one after a comma")
    func threeNames() {
        let displays = [external("A"), external("B"), external("C")]
        #expect(SyntheticNotchNote.text(for: displays) == "In use on A, B, and C.")
    }
}
