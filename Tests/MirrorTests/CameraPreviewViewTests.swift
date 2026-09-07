import AVFoundation
import AppKit
import Testing
@testable import Mirror

@MainActor
@Suite("Camera preview view")
struct CameraPreviewViewTests {
    /// The regression this guards: the frame used to be set from SwiftUI's
    /// `updateNSView`, which runs before AppKit lays the view out. `bounds` was
    /// still zero there, so the preview layer stayed zero-sized and the tab
    /// showed nothing at all.
    @Test("the preview layer fills the view once it has been laid out")
    func layerFillsBoundsAfterLayout() {
        let view = CameraPreviewView(frame: .zero)
        view.previewLayer = AVCaptureVideoPreviewLayer()

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        host.addSubview(view)
        view.frame = host.bounds
        view.layoutSubtreeIfNeeded()

        #expect(view.previewLayer?.frame == view.bounds)
        #expect(view.previewLayer?.frame != .zero)
    }

    @Test("a resize carries the layer with it")
    func layerFollowsResize() {
        let view = CameraPreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        view.previewLayer = AVCaptureVideoPreviewLayer()
        view.layoutSubtreeIfNeeded()

        view.setFrameSize(NSSize(width: 480, height: 270))
        view.layoutSubtreeIfNeeded()

        #expect(view.previewLayer?.frame == NSRect(x: 0, y: 0, width: 480, height: 270))
    }

    /// Swapping layers happens on every open: the module tears the session down
    /// on deactivate and hands back a new layer on the next activate.
    @Test("a new layer replaces the old one rather than stacking on top of it")
    func swappingLayersDropsThePrevious() {
        let view = CameraPreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let first = AVCaptureVideoPreviewLayer()
        let second = AVCaptureVideoPreviewLayer()

        view.previewLayer = first
        view.previewLayer = second
        view.layoutSubtreeIfNeeded()

        #expect(view.layer?.sublayers?.count == 1)
        #expect(view.layer?.sublayers?.first === second)
        #expect(first.superlayer == nil)
    }
}
