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
    @Published var isMoonModeEnabled = false
    @Published var previewScene: PhotoScene = .general

    // Device-reported manual camera limits. UI values are always clamped to this hardware.
    @Published var isoValue: Double = 100
    @Published var minimumISO: Double = 25
    @Published var maximumISO: Double = 1600
    @Published var shutterSeconds: Double = 1.0 / 120.0
    @Published var minimumShutterSeconds: Double = 1.0 / 8000.0
    @Published var maximumShutterSeconds: Double = 1.0 / 2.0
    @Published var focusPosition: Double = 1.0
    @Published var whiteBalanceTemperature: Double = 5500
    @Published var manualControlsEnabled = false
    @Published var moonStackSummary: String?

    weak var previewRenderer: MetalCameraPreviewRenderer?
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let visionQueue = DispatchQueue(label: "lunaracamera.vision.frames", qos: .userInitiated)
    private var lastMoonCheck = Date.distantPast
    private let sessionQueue = DispatchQueue(label: "lunaracamera.camera.session")
    private var configured = false
    private var activeCamera: AVCaptureDevice?
    private var activeMoonBurstDelegates: [MoonBurstPhotoDelegate] = []

    func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.isAuthorized = true }
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.isAuthorized = granted }
                if granted { self.configureAndStart() }
                else { DispatchQueue.main.async { self.errorMessage = "Permite el acceso a la cámara en Configuración." } }
            }
        default:
            DispatchQueue.main.async {
                self.isAuthorized = false
                self.errorMessage = "Permite el acceso a la cámara en Configuración."
            }
        }
    }

    private func configureAndStart() {
        sessionQueue.async {
            guard !self.configured else {
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.isRunning = self.session.isRunning }
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            defer { self.session.commitConfiguration() }

            let camera = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

            guard let camera,
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input),
                  self.session.canAddOutput(self.photoOutput) else {
                DispatchQueue.main.async { self.errorMessage = "No fue posible configurar la cámara." }
                return
            }

            self.activeCamera = camera
            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            self.photoOutput.isHighResolutionCaptureEnabled = true
            self.photoOutput.maxPhotoQualityPrioritization = .quality

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
                self.videoOutput.connection(with: .video)?.videoOrientation = .portrait
            }

            let format = camera.activeFormat
            let minISO = Double(format.minISO)
            let maxISO = Double(format.maxISO)
            let minShutter = max(CMTimeGetSeconds(format.minExposureDuration), 1.0 / 10000.0)
            let maxShutter = min(CMTimeGetSeconds(format.maxExposureDuration), 1.0)
            let maxZoom = min(format.videoMaxZoomFactor, 40.0)

            DispatchQueue.main.async {
                self.minimumISO = minISO
                self.maximumISO = maxISO
                self.isoValue = min(max(100, minISO), maxISO)
                self.minimumShutterSeconds = minShutter
                self.maximumShutterSeconds = max(minShutter, maxShutter)
                self.shutterSeconds = min(max(1.0 / 120.0, minShutter), maxShutter)
                self.maximumZoom = max(1.0, maxZoom)
            }

            self.configured = true
            self.session.startRunning()
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
            } catch {
                DispatchQueue.main.async { self.errorMessage = "No se pudo cambiar el zoom." }
            }
        }
    }

    func setManualExposure(seconds: Double, iso: Double) {
        let duration = min(max(seconds, minimumShutterSeconds), maximumShutterSeconds)
        let sensitivity = min(max(iso, minimumISO), maximumISO)
        DispatchQueue.main.async {
            self.shutterSeconds = duration
            self.isoValue = sensitivity
        }
        sessionQueue.async {
            guard let camera = self.activeCamera, camera.isExposureModeSupported(.custom) else { return }
            do {
                try camera.lockForConfiguration()
                let time = CMTimeMakeWithSeconds(duration, preferredTimescale: 1_000_000_000)
                camera.setExposureModeCustom(duration: time, iso: Float(sensitivity), completionHandler: nil)
                camera.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.errorMessage = "No se pudo aplicar ISO y velocidad manual." }
            }
        }
    }

    func setManualFocus(_ position: Double) {
        let clamped = min(max(position, 0), 1)
        DispatchQueue.main.async { self.focusPosition = clamped }
        sessionQueue.async {
            guard let camera = self.activeCamera, camera.isFocusModeSupported(.locked) else { return }
            do {
                try camera.lockForConfiguration()
                camera.setFocusModeLocked(lensPosition: Float(clamped), completionHandler: nil)
                camera.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.errorMessage = "No se pudo ajustar el enfoque manual." }
            }
        }
    }

    func setWhiteBalance(temperature: Double) {
        let clamped = min(max(temperature, 2500), 9000)
        DispatchQueue.main.async { self.whiteBalanceTemperature = clamped }
        sessionQueue.async {
            guard let camera = self.activeCamera, camera.isWhiteBalanceModeSupported(.locked) else { return }
            do {
                try camera.lockForConfiguration()
                let gains = camera.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(clamped), tint: 0))
                let maxGain = camera.maxWhiteBalanceGain
                let safeGains = AVCaptureDevice.WhiteBalanceGains(
                    redGain: min(max(gains.redGain, 1), maxGain),
                    greenGain: min(max(gains.greenGain, 1), maxGain),
                    blueGain: min(max(gains.blueGain, 1), maxGain)
                )
                camera.setWhiteBalanceModeLocked(with: safeGains, completionHandler: nil)
                camera.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.errorMessage = "No se pudo ajustar el balance de blancos." }
            }
        }
    }

    func capture() {
        sessionQueue.async {
            guard let camera = self.activeCamera else { return }
            let shouldUseMoonExposure = self.isMoonModeEnabled || self.isMoonDetected
            guard shouldUseMoonExposure || self.manualControlsEnabled else {
                self.capturePhotoNow()
                return
            }

            guard camera.isExposureModeSupported(.custom) else {
                self.capturePhotoNow()
                return
            }

            do {
                try camera.lockForConfiguration()
                let seconds = shouldUseMoonExposure
                    ? max(CMTimeGetSeconds(camera.activeFormat.minExposureDuration), 1.0 / 500.0)
                    : self.shutterSeconds
                let iso = shouldUseMoonExposure ? Double(camera.activeFormat.minISO) : self.isoValue
                if camera.isFocusModeSupported(.locked) {
                    let lens = shouldUseMoonExposure ? 1.0 : self.focusPosition
                    camera.setFocusModeLocked(lensPosition: Float(lens), completionHandler: nil)
                }
                let time = CMTimeMakeWithSeconds(seconds, preferredTimescale: 1_000_000_000)
                camera.setExposureModeCustom(duration: time, iso: Float(iso)) { _ in
                    self.capturePhotoNow()
                }
                camera.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.errorMessage = "No se pudo preparar la exposición." }
                self.capturePhotoNow()
            }
        }
    }

    /// Captures a short burst for local lunar lucky-imaging and aligned averaging.
    func captureMoonBurst() {
        sessionQueue.async {
            guard let camera = self.activeCamera else { return }
            guard camera.isExposureModeSupported(.custom) else {
                DispatchQueue.main.async { self.errorMessage = "Este dispositivo no permite exposición manual para el modo lunar." }
                return
            }
            do {
                try camera.lockForConfiguration()
                if camera.isFocusModeSupported(.locked) {
                    camera.setFocusModeLocked(lensPosition: 1.0, completionHandler: nil)
                }
                let seconds = max(CMTimeGetSeconds(camera.activeFormat.minExposureDuration), 1.0 / 500.0)
                let iso = Double(camera.activeFormat.minISO)
                let time = CMTimeMakeWithSeconds(seconds, preferredTimescale: 1_000_000_000)
                camera.setExposureModeCustom(duration: time, iso: Float(iso)) { _ in
                    self.sessionQueue.async { self.startMoonBurstCaptures(count: 7) }
                }
                camera.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.errorMessage = "No se pudo preparar la captura lunar." }
            }
        }
    }

    private func startMoonBurstCaptures(count: Int) {
        let collector = MoonBurstCollector(expectedCount: count) { [weak self] images in
            guard let self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let result = MoonStackProcessor.process(images)
                DispatchQueue.main.async {
                    self.capturedImage = result.image
                    self.moonStackSummary = result.usedFallback
                        ? "Ráfaga de \(result.inputFrameCount) · se eligió el fotograma más nítido"
                        : "Apiladas \(result.stackedFrameCount) de \(result.inputFrameCount) tomas · alineación local"
                    self.activeMoonBurstDelegates.removeAll()
                }
            }
        }

        activeMoonBurstDelegates = (0..<count).map { _ in
            MoonBurstPhotoDelegate { image in collector.receive(image) }
        }
        for delegate in activeMoonBurstDelegates {
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            settings.isHighResolutionPhotoEnabled = true
            settings.photoQualityPrioritization = .quality
            photoOutput.capturePhoto(with: settings, delegate: delegate)
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
        if let error {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.capturedImage = image }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        previewRenderer?.enqueue(pixelBuffer)
        guard Date().timeIntervalSince(lastMoonCheck) > 0.45 else { return }
        lastMoonCheck = Date()

        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer).perform([request])
            let labels = (request.results ?? []).prefix(12).map { $0.identifier.lowercased() }
            let text = labels.joined(separator: " ")
            let found = labels.contains { $0.contains("moon") || $0.contains("lunar") }
            let scene: PhotoScene
            if found { scene = .moon }
            else if ["food", "dish", "meal", "fruit", "vegetable"].contains(where: { text.contains($0) }) { scene = .food }
            else if ["person", "face", "portrait", "man", "woman"].contains(where: { text.contains($0) }) { scene = .portrait }
            else if ["car", "vehicle", "truck", "motorcycle", "automobile"].contains(where: { text.contains($0) }) { scene = .vehicle }
            else if ["landscape", "tree", "mountain", "sky", "plant", "forest"].contains(where: { text.contains($0) }) { scene = .landscape }
            else if ["document", "text", "paper", "book"].contains(where: { text.contains($0) }) { scene = .document }
            else { scene = .general }

            DispatchQueue.main.async {
                self.isMoonDetected = found
                self.previewScene = scene
            }
        } catch { }
    }
}


private final class MoonBurstPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    private var capturedImage: UIImage?

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        capturedImage = image
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completion(error == nil ? capturedImage : nil)
    }
}

private final class MoonBurstCollector {
    private let lock = NSLock()
    private let expectedCount: Int
    private var completedCount = 0
    private var images: [UIImage] = []
    private let completion: ([UIImage]) -> Void

    init(expectedCount: Int, completion: @escaping ([UIImage]) -> Void) {
        self.expectedCount = expectedCount
        self.completion = completion
    }

    func receive(_ image: UIImage?) {
        var finishedImages: [UIImage]?
        lock.lock()
        if let image { images.append(image) }
        completedCount += 1
        if completedCount == expectedCount {
            finishedImages = images
        }
        lock.unlock()
        if let finishedImages { completion(finishedImages) }
    }
}
