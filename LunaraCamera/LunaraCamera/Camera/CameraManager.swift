import AVFoundation
import Combine
import UIKit
import Vision

final class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var isRunning = false
    @Published var capturedImage: UIImage?
    @Published var errorMessage: String?
    @Published var zoomFactor: CGFloat = 1.0
    @Published var maximumZoom: CGFloat = 8.0
    @Published var isMoonDetected = false
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let visionQueue = DispatchQueue(label: "lunaracamera.vision.frames", qos: .userInitiated)
    private var lastMoonCheck = Date.distantPast
    private let sessionQueue = DispatchQueue(label: "lunaracamera.camera.session")
    private var configured = false
    private var activeCamera: AVCaptureDevice?

    func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.isAuthorized = true }; configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.isAuthorized = granted }
                if granted { self.configureAndStart() }
                else { DispatchQueue.main.async { self.errorMessage = "Permite el acceso a la cámara en Configuración." } }
            }
        default:
            DispatchQueue.main.async { self.isAuthorized = false; self.errorMessage = "Permite el acceso a la cámara en Configuración." }
        }
    }
    private func configureAndStart() {
        sessionQueue.async {
            guard !self.configured else {
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.isRunning = self.session.isRunning }; return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            defer { self.session.commitConfiguration() }
            let camera = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            guard let camera, let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput) else {
                DispatchQueue.main.async { self.errorMessage = "No fue posible configurar la cámara." }; return
            }
            self.activeCamera = camera
            self.session.addInput(input); self.session.addOutput(self.photoOutput)
            self.photoOutput.isHighResolutionCaptureEnabled = true
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            }
            let maxZoom = min(camera.activeFormat.videoMaxZoomFactor, 12.0)
            DispatchQueue.main.async { self.maximumZoom = max(1.0, maxZoom) }
            self.configured = true; self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }
    func setZoom(_ requested: CGFloat) {
        let clamped = min(max(requested, 1.0), maximumZoom)
        DispatchQueue.main.async { self.zoomFactor = clamped }
        sessionQueue.async {
            guard let camera = self.activeCamera else { return }
            do {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = min(max(clamped, 1.0), camera.activeFormat.videoMaxZoomFactor)
                camera.unlockForConfiguration()
            } catch { DispatchQueue.main.async { self.errorMessage = "No se pudo cambiar el zoom." } }
        }
    }
    func capture() {
        sessionQueue.async {
            guard let camera = self.activeCamera else { return }
            if self.isMoonDetected && camera.isExposureModeSupported(.custom) {
                do {
                    try camera.lockForConfiguration()
                    let minimumISO = camera.activeFormat.minISO
                    camera.setExposureModeCustom(duration: CMTime(value: 1, timescale: 250), iso: minimumISO) { _ in self.capturePhotoNow() }
                    camera.unlockForConfiguration()
                } catch {
                    DispatchQueue.main.async { self.errorMessage = "No se pudo preparar la exposición lunar." }
                    self.capturePhotoNow()
                }
            } else { self.capturePhotoNow() }
        }
    }
    private func capturePhotoNow() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.isHighResolutionPhotoEnabled = true
        settings.photoQualityPrioritization = photoOutput.maxPhotoQualityPrioritization == .quality ? .quality : .balanced
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
}
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { DispatchQueue.main.async { self.errorMessage = error.localizedDescription }; return }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.capturedImage = image }
    }
}
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastMoonCheck) > 0.45,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastMoonCheck = Date()
        let request = VNClassifyImageRequest()
        request.imageCropAndScaleOption = .centerCrop
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer).perform([request])
            let labels = (request.results ?? []).prefix(12).map { $0.identifier.lowercased() }
            let found = labels.contains { $0.contains("moon") || $0.contains("lunar") }
            DispatchQueue.main.async { if self.isMoonDetected != found { self.isMoonDetected = found } }
        } catch { }
    }
}