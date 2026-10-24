import AVFoundation
import SwiftUI

@Observable
final class CameraController {
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "skyglass.camera")
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var configured = false

    private(set) var isRunning = false
    private(set) var denied = false
    /// Field of view along the sensor's long side (vertical when held in portrait), degrees.
    private(set) var fieldOfView: Double = 65

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configure() } else { self.denied = true }
                }
            }
        default:
            denied = true
        }
    }

    func resume() {
        guard configured else { return }
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func pause() {
        queue.async { [session] in session.stopRunning() }
    }

    func setZoom(_ zoom: Double) {
        guard let device else { return }
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            let maxZoom = min(Double(device.activeFormat.videoMaxZoomFactor), 8)
            device.videoZoomFactor = CGFloat(min(max(zoom, 1), maxZoom))
            device.unlockForConfiguration()
        }
    }

    private func configure() {
        guard !configured,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        configured = true
        self.device = device
        queue.async { [session] in
            session.beginConfiguration()
            session.sessionPreset = .high
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            session.startRunning()
            let fov = Double(device.activeFormat.videoFieldOfView)
            let running = session.isRunning
            DispatchQueue.main.async {
                self.fieldOfView = fov > 1 ? fov : 65
                self.isRunning = running
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
