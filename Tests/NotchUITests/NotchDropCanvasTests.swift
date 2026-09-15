import CoreGraphics
import NotchCore
import SwiftUI
import Testing
@testable import NotchUI

/// What the drop's shapes do to each other, checked by rendering a frame and
/// reading the pixels back.
///
/// The fusing is done by a filter, not by geometry — two shapes near each other
/// become one, and a thread that gets too thin stops existing. Neither is
/// visible in the paths, so neither can be tested by inspecting them.
@MainActor
@Suite("Notch drop canvas")
struct NotchDropCanvasTests {
    private let width = 400
    private let height = 200
    /// The notch of a 14-inch MacBook Pro, centred in the canvas above.
    private let band = CGSize(width: 190, height: 32)

    // MARK: The frames

    private var hanging: NotchDropFrame {
        NotchDropFrame(
            bandSize: band,
            bandBottomRadius: 10,
            bead: NotchDropFrame.Bead(top: 66, width: 280, height: 48),
            neck: nil,
            contentOpacity: 1
        )
    }

    private var onTheNeck: NotchDropFrame {
        NotchDropFrame(
            bandSize: CGSize(width: 170, height: 50),
            bandBottomRadius: 26,
            bead: NotchDropFrame.Bead(top: 60, width: 150, height: 40),
            neck: NotchDropFrame.Neck(top: 42, bottom: 69, width: 24),
            contentOpacity: 0
        )
    }

    // MARK: What the shapes do to each other

    @Test("a drop still on its neck is one body with the notch")
    func theNeckFuses() throws {
        let pixels = try opacities(of: onTheNeck)

        // Between the band's bottom edge and the bead's top edge there is no
        // shape at all — only the thread, and only because the filter joins it
        // to both ends.
        #expect(pixels.alpha(x: 200, y: 55) > 0.9)
    }

    @Test("the neck joins only where it is, not across the whole gap")
    func theNeckIsLocal() throws {
        let pixels = try opacities(of: onTheNeck)

        #expect(pixels.alpha(x: 250, y: 55) < 0.1)
        #expect(pixels.alpha(x: 150, y: 55) < 0.1)
    }

    @Test("a drop that has let go is separated by clear screen")
    func theBreakIsReal() throws {
        let pixels = try opacities(of: hanging)

        #expect(pixels.alpha(x: 200, y: 16) > 0.9, "the band")
        #expect(pixels.alpha(x: 200, y: 90) > 0.9, "the bead")
        #expect(pixels.alpha(x: 200, y: 48) < 0.1, "the gap between them")
        #expect(pixels.alpha(x: 200, y: 150) < 0.1, "below the bead")
    }

    @Test("the notch keeps its concave top corners while the drop hangs")
    func theSilhouetteSurvivesTheFilter() throws {
        // The threshold rounds off whatever it touches, which would eat the one
        // part of the shape that has to stay exact: the sides sit a corner radius
        // inside the top edge, and a blurred band would bulge back out to meet it.
        let pixels = try opacities(of: hanging)

        // x = 105 is the band's top edge; below the corner the side is at 111.
        #expect(pixels.alpha(x: 106, y: 20) < 0.1)
        #expect(pixels.alpha(x: 115, y: 20) > 0.9)
    }

    // MARK: Rendering

    private struct Pixels {
        var bytes: [UInt8]
        var width: Int

        func alpha(x: Int, y: Int) -> Double {
            Double(bytes[(y * width + x) * 4 + 3]) / 255
        }
    }

    private func opacities(of frame: NotchDropFrame) throws -> Pixels {
        let renderer = ImageRenderer(
            content: NotchDropCanvas(frame: frame, topRadius: 6)
                .frame(width: CGFloat(width), height: CGFloat(height))
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        // A bitmap context stores its rows top down however its coordinate space
        // is oriented, so the first row in memory is the top of the drawn image —
        // which is what every coordinate in this suite means.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return Pixels(bytes: bytes, width: width)
    }
}
