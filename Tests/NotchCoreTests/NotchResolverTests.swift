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

    @Test("a menu bar taller than the safe area inset stretches the physical notch to match")
    func housingFollowsTheMenuBar() {
        // Measured on a 14-inch MacBook Pro: safeAreaInsets.top is 32 but the
        // menu bar band is 33, and the camera housing is as tall as the latter.
        var screen = builtIn
        screen.menuBarHeight = 33

        let metrics = NotchResolver.resolve(screen: screen, syntheticSize: syntheticSize)

        #expect(metrics.rect == CGRect(x: 641, y: 949, width: 230, height: 33))
    }

    @Test("a hidden menu bar does not shrink the physical notch below the auxiliary areas")
    func hiddenMenuBarKeepsAuxiliaryHeight() {
        var screen = builtIn
        screen.menuBarHeight = 0

        #expect(NotchResolver.resolve(screen: screen, syntheticSize: syntheticSize).rect.height == 32)
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

    @Test("a synthetic notch larger than the display is clamped to it")
    func oversizedSyntheticIsClamped() {
        let small = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            topSafeAreaInset: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        let metrics = NotchResolver.resolve(screen: small, syntheticSize: CGSize(width: 2000, height: 2000))

        #expect(metrics.kind == .synthetic)
        #expect(metrics.rect == CGRect(x: 0, y: 0, width: 1512, height: 982))
    }

    @Test("a synthetic notch lands on an integral x origin")
    func syntheticOriginIsIntegral() {
        let oddWidth = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1365, height: 768),
            topSafeAreaInset: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        let metrics = NotchResolver.resolve(screen: oddWidth, syntheticSize: syntheticSize)

        #expect(metrics.rect.origin.x == 583)
        #expect(metrics.rect.origin.x == metrics.rect.origin.x.rounded())
    }
}
