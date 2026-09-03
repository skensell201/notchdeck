import AVFoundation
import AppKit
import SwiftUI

/// Hosts the capture preview layer. SwiftUI has no native way to show one, so
/// this is the thinnest possible `NSViewRepresentable` around it.
struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        CATransaction.begin()
        // The layer is resized by the layout pass, not by an animation; without
        // this the preview lags behind the panel for a beat on every open.
        CATransaction.setDisableActions(true)
        layer.frame = nsView.bounds
        CATransaction.commit()
    }
}

struct MirrorView: View {
    let module: MirrorModule

    var body: some View {
        if let layer = module.previewLayer {
            CameraPreview(layer: layer)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        module.isMirrored.toggle()
                    } label: {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(5)
                            .background(Circle().fill(.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
                .scaleEffect(x: module.isMirrored ? -1 : 1, y: 1)
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
