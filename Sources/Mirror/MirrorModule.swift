import AVFoundation
import NotchCore
import NotchUI
import Observation
import SwiftUI
import Support

@MainActor
@Observable
public final class MirrorModule: NotchModule {
    public static let id = ModuleID("mirror")
    public let title = "Mirror"
    public let symbolName = "person.crop.square"

    public private(set) var status: PermissionStatus
    public private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    /// Flipped by default, because a mirror is what people expect to see of
    /// themselves; the camera itself is not mirrored.
    public var isMirrored = true

    private let camera: any CameraSessioning
    private let logger = Log.make("mirror")

    public init(camera: (any CameraSessioning)? = nil) {
        let camera = camera ?? CameraSession()
        self.camera = camera
        self.status = camera.status
    }

    // MARK: NotchModule

    /// The capture session lives exactly as long as the panel is open — the
    /// camera light must never outlast what the user can see.
    public func activate() {
        status = camera.status
        switch status {
        case .granted:
            previewLayer = camera.start()
            if previewLayer == nil {
                logger.notice("camera access is granted but no usable device was found")
            }
        case .notDetermined, .blocked:
            previewLayer = nil
        }
    }

    public func deactivate() {
        camera.stop()
        previewLayer = nil
    }

    public var hasLiveContent: Bool { false }
    public func peekView() -> AnyView? { nil }

    public func expandedView() -> AnyView {
        if status == .granted {
            AnyView(MirrorView(module: self))
        } else {
            AnyView(
                PermissionPrompt(permission: .camera, status: status) { [weak self] in
                    self?.requestAccess()
                }
            )
        }
    }

    private func requestAccess() {
        Task { [weak self] in
            guard let self else { return }
            status = await camera.requestAccess()
            if status == .granted {
                activate()
            }
        }
    }
}
