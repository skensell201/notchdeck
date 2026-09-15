import NotchCore
import SwiftUI

/// An announcement that leaves the notch: the band sags, a drop fills on a neck,
/// the neck breaks, and the drop carries the words down on its own.
///
/// Draws its own copy of the collapsed band on top of the shell's. Both are flat
/// black, so the copy is invisible where it overlaps and the only thing it adds
/// is the sag — which means the shell's shape, its animation and its hit testing
/// are all left exactly as they were.
struct NotchDropView: View {
    let payload: PeekPayload
    /// The collapsed band this hangs from, as the shell draws it.
    let band: CGSize
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    @State private var began = Date()
    @State private var contentWidth = NotchDropGeometry.minimumWidth

    /// The bead is cut to its words. A fixed width leaves half a capsule of
    /// empty black beside a short device name.
    private var beadWidth: CGFloat {
        min(
            max(contentWidth + 36, NotchDropGeometry.minimumWidth),
            NotchDropGeometry.maximumWidth
        )
    }

    var body: some View {
        TimelineView(.animation) { context in
            let frame = NotchDropGeometry.frame(
                elapsed: .seconds(max(context.date.timeIntervalSince(began), 0)),
                band: band,
                bottomRadius: bottomRadius,
                beadWidth: beadWidth
            )

            NotchDropCanvas(frame: frame, topRadius: topRadius)
                .compositingGroup()
                .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
                .overlay(alignment: .top) { words(frame) }
        }
        // Measured off-screen at its natural size, because the bead's width is
        // derived from the words and the words cannot be laid out in a bead whose
        // width is not known yet.
        .background(alignment: .top) {
            content
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    contentWidth = width
                }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func words(_ frame: NotchDropFrame) -> some View {
        if let bead = frame.bead {
            content
                .frame(width: bead.width, height: bead.height)
                .offset(y: bead.top)
                .opacity(frame.contentOpacity)
        }
    }

    private var content: some View {
        HStack(spacing: 11) {
            Image(systemName: payload.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(payload.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                if let detail = payload.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Self.colour(of: payload.tone))
                }
            }
            Spacer(minLength: 14)
            if let level = payload.level {
                Text(level.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
    }

    private static func colour(of tone: PeekTone) -> Color {
        switch tone {
        case .neutral: .white.opacity(0.6)
        case .positive: Color(red: 0.37, green: 0.83, blue: 0.61)
        case .caution: Color(red: 0.91, green: 0.63, blue: 0.37)
        }
    }
}

/// One frame of the drop, drawn.
///
/// Split from the view that animates it so that what the shapes do to each
/// other can be tested by rendering a frame, rather than by watching one.
struct NotchDropCanvas: View {
    let frame: NotchDropFrame
    let topRadius: CGFloat

    var body: some View {
        // Band, neck and bead in one layer, blurred and then thresholded back to
        // a hard edge. Two shapes that come within a blur radius of each other
        // fuse, which is what makes the neck a neck rather than a drawn-on tube.
        Canvas { context, size in
            let band = self.bandPath(in: size)
            let bead = frame.bead.map { self.beadPath($0, in: size) }

            context.drawLayer { fused in
                fused.addFilter(.alphaThreshold(min: 0.5, color: .black))
                fused.addFilter(.blur(radius: 6))
                fused.drawLayer { shapes in
                    shapes.fill(band, with: .color(.black))
                    if let neck = frame.neck {
                        shapes.fill(self.neckPath(neck, in: size), with: .color(.black))
                    }
                    if let bead {
                        shapes.fill(bead, with: .color(.black))
                    }
                }
            }

            // Drawn again unfiltered: the threshold rounds off whatever it
            // touches, and the notch's concave top corners are the one thing in
            // the shape that has to stay exact.
            context.fill(band, with: .color(.black))
            if let bead {
                context.fill(bead, with: .color(.black))
            }
        }
    }

    // MARK: Paths

    private func bandPath(in size: CGSize) -> Path {
        NotchShape(topCornerRadius: topRadius, bottomCornerRadius: frame.bandBottomRadius)
            .path(in: CGRect(
                x: (size.width - frame.bandSize.width) / 2,
                y: 0,
                width: frame.bandSize.width,
                height: frame.bandSize.height
            ))
    }

    private func beadPath(_ bead: NotchDropFrame.Bead, in size: CGSize) -> Path {
        Path(
            roundedRect: CGRect(
                x: (size.width - bead.width) / 2,
                y: bead.top,
                width: bead.width,
                height: bead.height
            ),
            cornerRadius: min(bead.height / 2, 22),
            style: .continuous
        )
    }

    /// An hourglass: wide where it meets the band, narrow at the waist, wide
    /// again where it meets the bead, so the fused silhouette has no shoulders.
    private func neckPath(_ neck: NotchDropFrame.Neck, in size: CGSize) -> Path {
        guard neck.bottom > neck.top, neck.width > 0 else { return Path() }
        let centre = size.width / 2
        let wide = neck.width * 0.65
        let waist = neck.width * 0.35
        let pull = (neck.bottom - neck.top) * 0.55

        var path = Path()
        path.move(to: CGPoint(x: centre - wide, y: neck.top))
        path.addCurve(
            to: CGPoint(x: centre - waist, y: neck.bottom),
            control1: CGPoint(x: centre - wide, y: neck.top + pull),
            control2: CGPoint(x: centre - waist, y: neck.bottom - pull)
        )
        path.addLine(to: CGPoint(x: centre + waist, y: neck.bottom))
        path.addCurve(
            to: CGPoint(x: centre + wide, y: neck.top),
            control1: CGPoint(x: centre + waist, y: neck.bottom - pull),
            control2: CGPoint(x: centre + wide, y: neck.top + pull)
        )
        path.closeSubpath()
        return path
    }
}
