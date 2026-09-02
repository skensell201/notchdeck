import AppKit
import NotchCore

public extension NSScreen {
    var notchDescription: ScreenDescription {
        ScreenDescription(
            frame: frame,
            topSafeAreaInset: safeAreaInsets.top,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea
        )
    }

    /// Stable identity across screen reconfigurations.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
