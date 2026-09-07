import AVFoundation
import AppKit
import SwiftUI

/// Layer-hosting view for the capture preview. The frame is set in `layout()`
/// rather than from SwiftUI: `updateNSView` runs before AppKit has laid the
/// view out, so at that point `bounds` is still zero and a layer sized from it
/// would never be visible.
final class CameraPreviewView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            guard previewLayer !== oldValue else { return }
            oldValue?.removeFromSuperlayer()
            if let previewLayer {
                layer?.addSublayer(previewLayer)
            }
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        // The layer follows the layout pass, not an animation; without this the
        // preview lags behind the panel for a beat on every open.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer
    let isMirrored: Bool

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(frame: .zero)
        view.previewLayer = layer
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        nsView.previewLayer = layer
        // Mirror through the capture connection rather than a SwiftUI
        // `scaleEffect`: the preview layer renders outside SwiftUI's own
        // compositing, so a transform on the hosting view does not reliably
        // reach it — and flipping the hosting view would flip the button
        // sitting on top of it too.
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
    }
}

struct MirrorView: View {
    let module: MirrorModule

    var body: some View {
        if let layer = module.previewLayer {
            CameraPreview(layer: layer, isMirrored: module.isMirrored)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        module.isMirrored.toggle()
                    } label: {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(module.isMirrored ? 0.85 : 0.45))
                            .padding(5)
                            .background(Circle().fill(.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .help(module.isMirrored ? "Show the camera's own view" : "Mirror the preview")
                    .padding(6)
                }
                .padding(.vertical, 4)
        } else if module.status == .granted {
            message("No camera found")
        } else {
            message("Camera unavailable")
        }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "video.slash")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
