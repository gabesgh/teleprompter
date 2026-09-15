import SwiftUI
import AVFoundation

/// Live camera preview backed by AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let camera: CameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspect   // show the whole recorded frame
        view.backgroundColor = .black
        camera.attach(previewLayer: view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
