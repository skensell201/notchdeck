import CoreGraphics
import NotchCore
import Testing
@testable import NotchUI

private let indigo = NotchTint(red: 0.169, green: 0.239, blue: 0.471)

@Suite("Panel fill")
struct NotchPanelFillTests {
    @Test("without a tint the panel stays the flat black it has always been")
    func noTint() {
        let stops = NotchPanelFill.stops(tint: nil, strength: 1, hold: 0.22)
        #expect(stops == [
            PanelFillStop(tint: .black, location: 0),
            PanelFillStop(tint: .black, location: 1)
        ])
    }

    @Test("black is held flat to the bottom of the camera housing")
    func holdsBlackAcrossTheHousing() {
        let stops = NotchPanelFill.stops(tint: indigo, strength: 1, hold: 0.22)
        #expect(stops.count == 3)
        #expect(stops[0] == PanelFillStop(tint: .black, location: 0))
        #expect(stops[1] == PanelFillStop(tint: .black, location: 0.22))
        #expect(stops[2] == PanelFillStop(tint: indigo, location: 1))
    }

    @Test("strength scales the tint towards black")
    func strengthScales() {
        let stops = NotchPanelFill.stops(tint: NotchTint(red: 0.8, green: 0.4, blue: 0.2), strength: 0.5, hold: 0.2)
        #expect(stops.last?.tint == NotchTint(red: 0.4, green: 0.2, blue: 0.1))
    }

    @Test("no strength is the same as no tint")
    func zeroStrengthIsBlack() {
        let stops = NotchPanelFill.stops(tint: indigo, strength: 0, hold: 0.22)
        #expect(stops == NotchPanelFill.stops(tint: nil, strength: 1, hold: 0.22))
    }

    @Test("strength beyond full is clamped rather than brightening past the colour")
    func strengthIsClamped() {
        let stops = NotchPanelFill.stops(tint: indigo, strength: 4, hold: 0.22)
        #expect(stops.last?.tint == indigo)
    }

    @Test("a hold that would swallow the whole panel leaves room for the fade")
    func holdIsClamped() {
        let stops = NotchPanelFill.stops(tint: indigo, strength: 1, hold: 2)
        #expect(stops[1].location == NotchPanelFill.holdCeiling)
        #expect(stops[1].location < stops[2].location)
    }

    @Test("a notch of no height drops the duplicated stop instead of doubling zero")
    func holdOfZero() {
        let stops = NotchPanelFill.stops(tint: indigo, strength: 1, hold: 0)
        #expect(stops == [
            PanelFillStop(tint: .black, location: 0),
            PanelFillStop(tint: indigo, location: 1)
        ])
    }

    @MainActor
    @Test("the fill a view model hands over holds black across its own housing")
    func modelMeasuresItsOwnHold() {
        let model = NotchViewModel(
            registry: ModuleRegistry(),
            metrics: NotchMetrics(rect: CGRect(x: 0, y: 0, width: 200, height: 30), kind: .physical),
            openSize: CGSize(width: 480, height: 150),
            appearance: NotchAppearance(tint: indigo, tintStrength: 1)
        )
        #expect(model.panelFillStops[1].location == 0.2)
    }

    @MainActor
    @Test("the collapsed band lies entirely inside the black hold, so the notch never shows a seam")
    func collapsedBandStaysBlack() {
        let model = NotchViewModel(
            registry: ModuleRegistry(),
            metrics: NotchMetrics(rect: CGRect(x: 0, y: 0, width: 200, height: 33), kind: .physical),
            openSize: CGSize(width: 480, height: 150),
            appearance: NotchAppearance(tint: indigo, tintStrength: 1)
        )
        model.mode = .closed

        // The fill is laid out against the open panel, never against whatever the
        // shape currently measures: the visible slice of it while collapsed is the
        // band's height over that, and it has to stop short of the first colour.
        let visible = model.targetSize.height / model.panelFillHeight
        #expect(visible <= model.panelFillStops[1].location)
    }

    @MainActor
    @Test("opening the notch does not move the fill, only reveals more of it")
    func fillHeightIgnoresMode() {
        let model = NotchViewModel(
            registry: ModuleRegistry(),
            metrics: NotchMetrics(rect: CGRect(x: 0, y: 0, width: 200, height: 33), kind: .physical),
            openSize: CGSize(width: 480, height: 150),
            appearance: NotchAppearance(tint: indigo, tintStrength: 1)
        )

        model.mode = .closed
        let closed = model.panelFillHeight
        model.mode = .open
        #expect(model.panelFillHeight == closed)
        #expect(closed == 150)
    }
}
