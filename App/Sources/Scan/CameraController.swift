import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class CameraController: NSObject, ObservableObject {
    @Published private(set) var isReady = false

    nonisolated(unsafe) let session = AVCaptureSession()
    private nonisolated(unsafe) let output = AVCapturePhotoOutput()

    private let sessionQueue = DispatchQueue(label: "listnr.camera")
    private var configured = false
    private var pendingCapture: ((UIImage?) -> Void)?

    override init() {
        super.init()
        if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
            isReady = false
        }
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            runSession(configureIfNeeded: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard granted else { return }
                    self?.runSession(configureIfNeeded: true)
                }
            }
        default:
            isReady = false
        }
    }

    func stop() {
        let session = session
        sessionQueue.async {
            session.stopRunning()
        }
        isReady = false
    }

    func captureStill(completion: @escaping (UIImage?) -> Void) {
        guard isReady, pendingCapture == nil else {
            completion(nil)
            return
        }
        pendingCapture = completion
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    private func runSession(configureIfNeeded: Bool) {
        let session = session
        let output = output
        let firstRun = configureIfNeeded && !configured
        if firstRun { configured = true }
        sessionQueue.async {
            if firstRun {
                session.beginConfiguration()
                session.sessionPreset = .photo
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                    if session.canAddOutput(output) {
                        session.addOutput(output)
                    }
                }
                session.commitConfiguration()
            }
            if !session.isRunning {
                session.startRunning()
            }
            let hasInput = !session.inputs.isEmpty
            Task { @MainActor in self.isReady = hasInput }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        Task { @MainActor in
            let completion = self.pendingCapture
            self.pendingCapture = nil
            completion?(image)
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        if let layer = view.layer as? AVCaptureVideoPreviewLayer {
            layer.session = session
            layer.videoGravity = .resizeAspectFill
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
