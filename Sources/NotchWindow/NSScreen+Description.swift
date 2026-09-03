import AppKit
import NotchCore

public extension NSScreen {
    var notchDescription: ScreenDescription {
        ScreenDescription(
            frame: frame,
            topSafeAreaInset: safeAreaInsets.top,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea,
            menuBarHeight: frame.maxY - visibleFrame.maxY
        )
    }

    /// Stable identity across screen reconfigurations.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
