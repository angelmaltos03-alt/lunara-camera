import SwiftUI
import AVFoundation
import MetalKit
import CoreImage
import CoreVideo

struct CameraPreview: UIViewRepresentable {
    let camera: CameraManager
    let mode: PhotoEditMode
    let look: PhotoLook
    let intensity: Double
    let adjustments: PhotoAdjustments

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MTKView(frame: .zero, device: nil)
        }
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.backgroundColor = .black

        let renderer = MetalCameraPreviewRenderer(device: device)
        renderer.update(mode: mode, look: look, intensity: intensity, adjustments: adjustments, scene: camera.previewScene)
        view.delegate = renderer
        context.coordinator.renderer = renderer
        camera.previewRenderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.update(
            mode: mode, look: look, intensity: intensity,
            adjustments: adjustments, scene: camera.previewScene
        )
        camera.previewRenderer = context.coordinator.renderer
    }

    final class Coordinator {
        var renderer: MetalCameraPreviewRenderer?
    }
}

final class MetalCameraPreviewRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let processor = PhotoProcessor()
    private let lock = NSLock()
    private var latestImage: CIImage?
    private var mode: PhotoEditMode = .auto
    private var look: PhotoLook = .natural
    private var intensity = 0.55
    private var adjustments = PhotoAdjustments()
    private var scene: PhotoScene = .general

    init(device: MTLDevice) {
        commandQueue = device.makeCommandQueue()!
        ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        super.init()
    }

    func update(mode: PhotoEditMode, look: PhotoLook, intensity: Double, adjustments: PhotoAdjustments, scene: PhotoScene) {
        lock.lock()
        self.mode = mode
        self.look = look
        self.intensity = intensity
        self.adjustments = adjustments
        self.scene = scene
        lock.unlock()
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        lock.lock()
        latestImage = image
        lock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        lock.lock()
        let source = latestImage
        let currentMode = mode
        let currentLook = look
        let currentIntensity = intensity
        let currentAdjustments = adjustments
        let currentScene = scene
        lock.unlock()
        guard let source else { return }

        let developed = processor.develop(
            source,
            scene: currentScene,
            mode: currentMode,
            look: currentLook,
            intensity: currentIntensity,
            adjustments: currentAdjustments
        )

        let target = CGRect(origin: .zero, size: view.drawableSize)
        let sourceExtent = developed.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0, target.width > 0, target.height > 0 else { return }
        let scale = max(target.width / sourceExtent.width, target.height / sourceExtent.height)
        let scaled = developed.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let cropX = scaled.extent.minX + (scaled.extent.width - target.width) / 2
        let cropY = scaled.extent.minY + (scaled.extent.height - target.height) / 2
        let cropped = scaled.cropped(to: CGRect(x: cropX, y: cropY, width: target.width, height: target.height))

        ciContext.render(
            cropped,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: target,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
