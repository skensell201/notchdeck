import AVFoundation
import NotchUI

/// The camera, behind a seam so the module can be reasoned about without one.
@MainActor
public protocol CameraSessioning: AnyObject {
    var status: PermissionStatus { get }
    func requestAccess() async -> PermissionStatus
    /// Starts capture and returns the layer to display, or nil when access is
    /// missing or no camera exists.
    func start() -> AVCaptureVideoPreviewLayer?
    func stop()
}

@MainActor
public final class CameraSession: CameraSessioning {
    private var session: AVCaptureSession?
    private var layer: AVCaptureVideoPreviewLayer?

    public init() {}

    public var status: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .blocked
        }
    }

    public func requestAccess() async -> PermissionStatus {
        // Only ask while undetermined: once denied, the system silently returns
        // false forever and the only way forward is System Settings.
        guard status == .notDetermined else { return status }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return status
    }

    public func start() -> AVCaptureVideoPreviewLayer? {
        guard status == .granted else { return nil }
        if let layer { return layer }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device) else {
            return nil
        }

        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill

        self.session = session
        self.layer = layer

        // startRunning blocks for a beat; the camera light must not stall the
        // panel opening. AVCaptureSession is not Sendable, but Apple documents
        // startRunning as safe to call off the main queue, which is the whole
        // reason for doing it here.
        nonisolated(unsafe) let starting = session
        Task.detached { starting.startRunning() }
        return layer
    }

    public func stop() {
        // Tear the session down rather than pausing it, so the camera light is
        // never on for longer than the panel is open.
        session?.stopRunning()
        session = nil
        layer = nil
    }
}
