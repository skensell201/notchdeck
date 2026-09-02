import CoreGraphics
import Testing
@testable import NotchCore

@Suite("Notch resolver")
struct NotchResolverTests {
    private let syntheticSize = CGSize(width: 200, height: 32)

    /// A 14-inch MacBook Pro: 1512x982 points, 32pt notch, camera housing 230pt wide.
    private var builtIn: ScreenDescription {
        ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            topSafeAreaInset: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 641, height: 32),
            auxiliaryTopRightArea: CGRect(x: 871, y: 950, width: 641, height: 32)
        )
    }

    @Test("a built-in display yields the physical notch rect between the auxiliary areas")
    func physicalNotch() {
        let metrics = NotchResolver.resolve(screen: builtIn, syntheticSize: syntheticSize)

        #expect(metrics.kind == .physical)
        #expect(metrics.rect == CGRect(x: 641, y: 950, width: 230, height: 32))
    }

    @Test("a notchless display yields a synthetic notch centred at its top edge")
    func syntheticNotch() {
        let external = ScreenDescription(
            frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
            topSafeAreaInset: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        let metrics = NotchResolver.resolve(screen: external, syntheticSize: syntheticSize)

        #expect(metrics.kind == .synthetic)
        #expect(metrics.rect == CGRect(x: 2372, y: 1048, width: 200, height: 32))
    }

    @Test("a display reporting auxiliary areas but no safe area inset falls back to synthetic")
    func inconsistentDisplayFallsBack() {
        let odd = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            topSafeAreaInset: 0,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 641, height: 32),
            auxiliaryTopRightArea: CGRect(x: 871, y: 950, width: 641, height: 32)
        )

        #expect(NotchResolver.resolve(screen: odd, syntheticSize: syntheticSize).kind == .synthetic)
    }

    @Test("overlapping auxiliary areas fall back to synthetic instead of a negative width")
    func overlappingAreasFallBack() {
        let broken = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            topSafeAreaInset: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 800, height: 32),
            auxiliaryTopRightArea: CGRect(x: 700, y: 950, width: 812, height: 32)
        )

        let metrics = NotchResolver.resolve(screen: broken, syntheticSize: syntheticSize)

        #expect(metrics.kind == .synthetic)
        #expect(metrics.rect.width == 200)
    }

    @Test("a synthetic notch on a display left of the origin is still centred on that display")
    func negativeOriginIsHandled() {
        let leftOfMain = ScreenDescription(
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            topSafeAreaInset: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        let metrics = NotchResolver.resolve(screen: leftOfMain, syntheticSize: syntheticSize)

        #expect(metrics.rect.midX == -960)
    }
}
