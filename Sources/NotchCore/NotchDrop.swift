import CoreGraphics
import Foundation

/// How long a drop lives, from the first sag to the last of it being drawn back in.
///
/// The shell cannot animate a view that has been removed, so a drop payload's
/// `duration` has to be `total`: the mode must outlast the animation, not the
/// other way round.
public enum NotchDropTiming {
    /// The band sags, the drop fills, the neck breaks, the words fade in.
    public static let entering = Duration.milliseconds(900)
    /// How long the drop hangs there being read.
    public static let hold = Duration.milliseconds(1700)
    /// The neck grows back and the drop is swallowed.
    public static let leaving = Duration.milliseconds(780)
    public static var total: Duration { entering + hold + leaving }
}

/// One frame of the drop, in points, measured from the top of the screen.
///
/// Everything here is geometry the shell fills black. Which of the three shapes
/// exist at a given moment is the whole animation: the neck is what makes the
/// drop one body with the notch, and its absence is what makes it detached.
public struct NotchDropFrame: Equatable, Sendable {
    /// The hanging drop, once there is one.
    public struct Bead: Equatable, Sendable {
        public var top: CGFloat
        public var width: CGFloat
        public var height: CGFloat

        public init(top: CGFloat, width: CGFloat, height: CGFloat) {
            self.top = top
            self.width = width
            self.height = height
        }

        public var bottom: CGFloat { top + height }
    }

    /// The thread between band and bead. Nil once it has thinned past holding.
    public struct Neck: Equatable, Sendable {
        public var top: CGFloat
        public var bottom: CGFloat
        /// Width at the waist. The ends flare out into whatever they meet.
        public var width: CGFloat

        public init(top: CGFloat, bottom: CGFloat, width: CGFloat) {
            self.top = top
            self.bottom = bottom
            self.width = width
        }
    }

    /// The collapsed band, which sags and draws in while the drop forms.
    public var bandSize: CGSize
    public var bandBottomRadius: CGFloat
    public var bead: Bead?
    public var neck: Neck?
    public var contentOpacity: Double

    public init(
        bandSize: CGSize,
        bandBottomRadius: CGFloat,
        bead: Bead? = nil,
        neck: Neck? = nil,
        contentOpacity: Double = 0
    ) {
        self.bandSize = bandSize
        self.bandBottomRadius = bandBottomRadius
        self.bead = bead
        self.neck = neck
        self.contentOpacity = contentOpacity
    }
}

/// The shape of the drop at any moment in its life.
///
/// A pure function of elapsed time, which is the only way this is testable: the
/// curves are piecewise and overlapping, and reading them off a running
/// animation would be guesswork.
public enum NotchDropGeometry {
    // Tuned against a 190x32 pt notch — a 14-inch MacBook Pro — and expressed as
    // points added to that notch rather than as multiples of it, because the
    // weight of a drop does not depend on how wide the camera housing is.

    /// How far the band sags before it lets go.
    public static let sag: CGFloat = 26
    /// How far the band draws in at its widest sag. Surface tension pulls a
    /// hanging drop's shoulders inwards, and without this the band just grows.
    public static let waist: CGFloat = 20
    /// Added to the closed bottom radius while sagging, so the band bellies out.
    public static let sagRadius: CGFloat = 19
    /// How far below the band the bead settles.
    public static let hangDepth: CGFloat = 34
    public static let beadHeight: CGFloat = 48
    /// The bead is never narrower than this, however short the words are, and
    /// never wider than this, however long.
    public static let minimumWidth: CGFloat = 236
    public static let maximumWidth: CGFloat = 380

    /// How far the settling wobble can carry a bead past where it comes to rest.
    /// Small, and the one part of this that is not decoration: a panel sized to
    /// the resting place alone clips the overshoot off against the window edge.
    static let settle: CGFloat = 5

    /// The lowest point anything is ever drawn at. The panel must reserve this
    /// much height or the bead is clipped off at the window edge.
    public static func reach(bandHeight: CGFloat) -> CGFloat {
        bandHeight + hangDepth + beadHeight + settle
    }

    /// - Parameters:
    ///   - elapsed: time since the drop began, across its whole life.
    ///   - band: the collapsed band the drop hangs from.
    ///   - bottomRadius: the closed band's bottom corner radius.
    ///   - beadWidth: what the bead settles at, already sized to its content.
    public static func frame(
        elapsed: Duration,
        band: CGSize,
        bottomRadius: CGFloat,
        beadWidth: CGFloat
    ) -> NotchDropFrame {
        let t = milliseconds(elapsed)
        let entering = milliseconds(NotchDropTiming.entering)
        let leaving = entering + milliseconds(NotchDropTiming.hold)

        if t < entering {
            return forming(t, band, bottomRadius, beadWidth)
        }
        if t < leaving {
            return hanging(band, bottomRadius, beadWidth)
        }
        return swallowing(t - leaving, band, bottomRadius, beadWidth)
    }

    // MARK: The three phases

    private static func forming(
        _ t: Double, _ band: CGSize, _ radius: CGFloat, _ beadWidth: CGFloat
    ) -> NotchDropFrame {
        let height = (t < 220
            ? seg(t, 0, 220, band.height, band.height + sag, .out)
            : seg(t, 220, 620, band.height + sag, band.height, .inOut))
            + wob(t, from: 520, amplitude: 2.5, frequency: 3.6, decay: 8)
        let width = (t < 220
            ? seg(t, 0, 220, band.width, band.width - waist, .out)
            : seg(t, 220, 580, band.width - waist, band.width, .inOut))
            + wob(t, from: 520, amplitude: 3, frequency: 3.4, decay: 7)
        let bottom = t < 220
            ? seg(t, 0, 220, radius, radius + sagRadius, .out)
            : seg(t, 220, 620, radius + sagRadius, radius, .inOut)

        var frame = NotchDropFrame(
            bandSize: CGSize(width: width, height: height),
            bandBottomRadius: bottom,
            bead: nil,
            neck: nil,
            contentOpacity: Double(seg(t, 560, 690, 0, 1, .out))
        )

        guard t >= 150 else { return frame }

        // Clings and fills, then lets go: accelerating away from the notch, then
        // landing. A single ease here reads as the drop being pushed down rather
        // than falling off.
        let top = (t < 360
            ? seg(t, 150, 360, band.height - 2, band.height + 18, .easeIn)
            : seg(t, 360, 560, band.height + 18, band.height + hangDepth, .out))
            + wob(t, from: 520, amplitude: 2.5, frequency: 3, decay: 7)
        // While it hangs it is round; it only relaxes into a capsule once free.
        let bud = min(120, band.width * 0.63)
        let swell = min(150, band.width * 0.79)
        let beadWide = (t < 480
            ? seg(t, 150, 480, bud, swell, .out)
            : seg(t, 480, 700, swell, beadWidth, .out))
            + wob(t, from: 700, amplitude: 4, frequency: 3, decay: 6)
        let beadHigh = (t < 480
            ? seg(t, 150, 480, 34, 44, .out)
            : seg(t, 480, 700, 44, beadHeight, .out))
            + wob(t, from: 700, amplitude: 2, frequency: 3.6, decay: 6)

        frame.bead = NotchDropFrame.Bead(top: top, width: beadWide, height: beadHigh)
        // Past three points the alpha threshold stops holding a thread this long,
        // so the break is the filter's decision rather than a keyframe.
        if t < 520 {
            frame.neck = NotchDropFrame.Neck(
                top: height - 8,
                bottom: top + 9,
                width: seg(t, 200, 520, 44, 3, .easeIn)
            )
        }
        return frame
    }

    private static func hanging(
        _ band: CGSize, _ radius: CGFloat, _ beadWidth: CGFloat
    ) -> NotchDropFrame {
        NotchDropFrame(
            bandSize: band,
            bandBottomRadius: radius,
            bead: NotchDropFrame.Bead(
                top: band.height + hangDepth,
                width: beadWidth,
                height: beadHeight
            ),
            neck: nil,
            contentOpacity: 1
        )
    }

    private static func swallowing(
        _ t: Double, _ band: CGSize, _ radius: CGFloat, _ beadWidth: CGFloat
    ) -> NotchDropFrame {
        // The band only opens to take the bead back once the bead is close, which
        // is why nothing happens here for the first third of a second.
        let height = t < 380
            ? band.height
            : (t < 560
                ? seg(t, 380, 560, band.height, band.height + 18, .out)
                : seg(t, 560, 780, band.height + 18, band.height, .inOut))
        let bottom = t < 380
            ? radius
            : (t < 560
                ? seg(t, 380, 560, radius, radius + 17, .out)
                : seg(t, 560, 780, radius + 17, radius, .inOut))

        var frame = NotchDropFrame(
            bandSize: CGSize(width: band.width, height: height),
            bandBottomRadius: bottom,
            bead: nil,
            neck: nil,
            contentOpacity: Double(seg(t, 0, 130, 1, 0, .easeIn))
        )

        guard t < 600 else { return frame }

        let top = seg(t, 110, 560, band.height + hangDepth, band.height - 18, .inOut)
        frame.bead = NotchDropFrame.Bead(
            top: top,
            width: seg(t, 110, 560, beadWidth, min(128, band.width * 0.67), .inOut),
            height: seg(t, 110, 560, beadHeight, 28, .inOut)
        )
        // Going up the thread thickens instead of thinning: the band is pulling,
        // not letting go.
        if t > 230 {
            frame.neck = NotchDropFrame.Neck(
                top: height - 8,
                bottom: top + 9,
                width: seg(t, 230, 520, 3, 44, .out)
            )
        }
        return frame
    }

    // MARK: Curves

    private enum Ease {
        case out, easeIn, inOut

        func callAsFunction(_ t: Double) -> Double {
            switch self {
            case .out: 1 - pow(1 - t, 3)
            case .easeIn: t * t * t
            case .inOut: t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            }
        }
    }

    /// One eased segment of a piecewise curve, flat outside its window.
    private static func seg(
        _ t: Double, _ start: Double, _ end: Double,
        _ from: CGFloat, _ to: CGFloat, _ ease: Ease
    ) -> CGFloat {
        if t <= start { return from }
        if t >= end { return to }
        return from + (to - from) * CGFloat(ease((t - start) / (end - start)))
    }

    /// A decaying wobble, added on top of a curve so a shape settles rather than
    /// stopping dead. Zero before it starts, and vanishingly small after.
    private static func wob(
        _ t: Double, from start: Double,
        amplitude: CGFloat, frequency: Double, decay: Double
    ) -> CGFloat {
        guard t >= start else { return 0 }
        let seconds = (t - start) / 1000
        return amplitude * CGFloat(exp(-decay * seconds) * sin(2 * .pi * frequency * seconds))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}
