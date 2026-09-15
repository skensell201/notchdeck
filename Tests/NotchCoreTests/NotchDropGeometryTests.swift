import CoreGraphics
import Testing
@testable import NotchCore

@Suite("Notch drop geometry")
struct NotchDropGeometryTests {
    /// A 14-inch MacBook Pro's notch, which every constant was tuned against.
    private let band = CGSize(width: 190, height: 32)
    private let radius: CGFloat = 10
    private let beadWidth: CGFloat = 280

    private func frame(at milliseconds: Int) -> NotchDropFrame {
        NotchDropGeometry.frame(
            elapsed: .milliseconds(milliseconds),
            band: band,
            bottomRadius: radius,
            beadWidth: beadWidth
        )
    }

    // MARK: The ends

    @Test("nothing has happened at the first frame")
    func startsAsTheClosedNotch() {
        let start = frame(at: 0)

        #expect(start.bandSize == band)
        #expect(start.bandBottomRadius == radius)
        #expect(start.bead == nil)
        #expect(start.neck == nil)
        #expect(start.contentOpacity == 0)
    }

    @Test("the band is closed again and the drop is gone once it is over")
    func endsAsTheClosedNotch() {
        let end = frame(at: 3380)

        #expect(end.bandSize.width == band.width)
        #expect(end.bandSize.height == band.height)
        #expect(end.bandBottomRadius == radius)
        #expect(end.bead == nil)
        #expect(end.neck == nil)
        #expect(end.contentOpacity == 0)
    }

    @Test("the drop hangs still, fully readable, for the whole hold")
    func restsWhileItIsRead() {
        for t in stride(from: 900, through: 2590, by: 100) {
            let resting = frame(at: t)
            #expect(resting.bandSize == band)
            #expect(resting.neck == nil)
            #expect(resting.contentOpacity == 1)
            #expect(resting.bead?.width == beadWidth)
            #expect(resting.bead?.height == NotchDropGeometry.beadHeight)
            #expect(resting.bead?.top == band.height + NotchDropGeometry.hangDepth)
        }
    }

    // MARK: Forming

    @Test("the band sags and draws in before anything leaves it")
    func sagsBeforeItLetsGo() {
        let sagging = frame(at: 220)

        #expect(sagging.bandSize.height > band.height + NotchDropGeometry.sag - 1)
        // Surface tension: a hanging drop pulls its own shoulders in.
        #expect(sagging.bandSize.width < band.width)
        #expect(sagging.bandBottomRadius > radius)
    }

    @Test("the drop hangs on a neck before it breaks free")
    func hangsOnANeckFirst() {
        let hanging = frame(at: 300)

        #expect(hanging.neck != nil)
        // One body: the neck reaches into both shapes rather than bridging a gap.
        #expect(hanging.neck!.top < hanging.bandSize.height)
        #expect(hanging.neck!.bottom > hanging.bead!.top)
    }

    @Test("the neck thins all the way to the break, and never comes back")
    func neckThinsToNothing() {
        var previous = CGFloat.greatestFiniteMagnitude
        for t in stride(from: 200, through: 510, by: 10) {
            let width = frame(at: t).neck?.width
            #expect(width != nil)
            #expect(width! <= previous)
            previous = width!
        }
        // Under the blur radius the fused shape cannot hold a thread this long,
        // which is what makes the break the filter's decision and not a keyframe.
        #expect(previous < 8)
        for t in stride(from: 520, through: 900, by: 20) {
            #expect(frame(at: t).neck == nil)
        }
    }

    @Test("the drop is clear of the band by the time the neck lets go")
    func detachesCleanly() {
        let broken = frame(at: 560)

        #expect(broken.bead!.top > broken.bandSize.height)
    }

    @Test("the words only appear once the drop has landed")
    func wordsWaitForTheLanding() {
        #expect(frame(at: 400).contentOpacity == 0)
        #expect(frame(at: 560).contentOpacity == 0)
        #expect(frame(at: 700).contentOpacity > 0.5)
    }

    // MARK: Leaving

    @Test("the drop is swallowed rather than faded out")
    func isSwallowedOnTheWayBack() {
        // Rises...
        #expect(frame(at: 2900).bead!.top < frame(at: 2700).bead!.top)
        // ...on a neck that thickens as the band pulls it in...
        #expect(frame(at: 3000).neck!.width > frame(at: 2900).neck!.width)
        // ...and the band opens to take it.
        #expect(frame(at: 3100).bandSize.height > band.height)
    }

    @Test("the words are gone before the drop starts moving")
    func wordsLeaveFirst() {
        #expect(frame(at: 2740).contentOpacity == 0)
        #expect(frame(at: 2740).bead != nil)
    }

    // MARK: The invariant the panel depends on

    @Test("nothing is ever drawn below the reach the panel reserves")
    func staysInsideItsPanel() {
        let reach = NotchDropGeometry.reach(bandHeight: band.height)

        for t in stride(from: 0, through: 3400, by: 5) {
            let sample = frame(at: t)
            #expect(sample.bandSize.height <= reach)
            if let bead = sample.bead {
                #expect(bead.bottom <= reach)
            }
            if let neck = sample.neck {
                #expect(neck.bottom <= reach)
            }
        }
    }

    @Test("a synthetic notch narrower than the drop still forms a drop inside it")
    func survivesATinyNotch() {
        let tiny = CGSize(width: 90, height: 20)
        let forming = NotchDropGeometry.frame(
            elapsed: .milliseconds(300),
            band: tiny,
            bottomRadius: radius,
            beadWidth: NotchDropGeometry.minimumWidth
        )

        // The bud is a fraction of the band while it hangs, not a fixed width
        // that would be wider than the notch it is hanging from.
        #expect(forming.bead!.width < tiny.width)
    }
}
