import NotchCore
import SwiftUI
import Testing
@testable import NotchUI

/// How wide the notch is while it is closed, which is the whole of what the
/// collapsed setting decides.
@MainActor
@Suite("Collapsed band")
struct CollapsedBandTests {
    /// A module with something live to show, which is all the registry asks of it.
    private final class PlayingModule: NotchModule {
        static let id = ModuleID("playing")
        let title = "Playing"
        let symbolName = "play"
        func activate() {}
        func deactivate() {}
        func expandedView() -> AnyView { AnyView(EmptyView()) }
        func peekView() -> AnyView? { AnyView(EmptyView()) }
        var hasLiveContent: Bool { true }
    }

    private func model(playing: Bool) -> NotchViewModel {
        let registry = ModuleRegistry()
        if playing {
            registry.register(PlayingModule())
        }
        return NotchViewModel(
            registry: registry,
            metrics: NotchMetrics(rect: CGRect(x: 0, y: 0, width: 200, height: 33), kind: .physical),
            openSize: CGSize(width: 480, height: 150)
        )
    }

    @Test("music playing does not widen the closed notch")
    func playingLeavesTheNotchAlone() {
        let model = model(playing: true)
        model.mode = .closed

        #expect(model.targetSize == model.closedSize)
    }

    @Test("turning the setting on brings the wide band back")
    func theSettingWidensIt() {
        let model = model(playing: true)
        model.mode = .closed
        model.showsLiveContentWhenClosed = true

        #expect(model.targetSize == model.peekSize)
        #expect(model.targetSize.width > model.closedSize.width)
    }

    @Test("the setting does nothing on its own, with nothing live to show")
    func theSettingNeedsSomethingToShow() {
        let model = model(playing: false)
        model.mode = .closed
        model.showsLiveContentWhenClosed = true

        #expect(model.targetSize == model.closedSize)
    }

    @Test("an announcement still widens the band, whatever the setting says")
    func announcementsAreNotTheSameThing() {
        // A peek is timed and asked for by the machine; the collapsed band is a
        // standing choice about how the notch looks while nothing is happening.
        let model = model(playing: false)
        model.mode = .peek(PeekPayload(id: "charging", title: "Charging"))

        #expect(model.targetSize == model.peekSize)
    }
}
