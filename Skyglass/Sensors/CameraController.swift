import AVFoundation
import SwiftUI

@Observable
final class CameraController {
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "skyglass.camera")
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private let frameQueue = DispatchQueue(label: "skyglass.camera.frames")
    @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
    /// Feeds black-and-white frames to the preview while Boring Mode is on.
    @ObservationIgnored let monoFrames = MonoFrameSink()

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
            // Full-range luma: plane 0 is already a black-and-white image of the scene.
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self.monoFrames, queue: self.frameQueue)
            if session.canAddOutput(self.videoOutput) {
                session.addOutput(self.videoOutput)
                if let connection = self.videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
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

/// Turns camera frames into greyscale images for Boring Mode. SwiftUI's grayscale can't reach the
/// video layer and iOS ignores layer blend filters, so the luma plane is drawn over the preview instead.
final class MonoFrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _enabled = false
    private weak var _layer: CALayer?

    var enabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue } }
    }

    func attach(_ layer: CALayer) { lock.withLock { _layer = layer } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard enabled, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        guard let provider = CGDataProvider(data: Data(bytes: base, count: rowBytes * height) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: rowBytes,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, let layer = self.lock.withLock({ self._layer }) else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = image
            CATransaction.commit()
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var mono = false
    var monoFrames: MonoFrameSink?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        monoFrames?.attach(view.monoLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        monoFrames?.enabled = mono
        uiView.mono = mono
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        /// Black-and-white frames drawn over the colour preview while Boring Mode is on.
        let monoLayer: CALayer = {
            let l = CALayer()
            l.contentsGravity = .resizeAspectFill
            l.backgroundColor = UIColor.black.cgColor
            l.isHidden = true
            return l
        }()

        var mono = false {
            didSet {
                monoLayer.isHidden = !mono
                if !mono { monoLayer.contents = nil }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if monoLayer.superlayer == nil { layer.addSublayer(monoLayer) }
            monoLayer.frame = bounds
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
