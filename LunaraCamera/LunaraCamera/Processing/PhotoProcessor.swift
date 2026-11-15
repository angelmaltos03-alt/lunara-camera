import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct PhotoProcessor {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func enhance(_ image: UIImage, scene: PhotoScene) -> UIImage {
        guard let input = CIImage(image: image) else { return image }
        let controls = CIFilter.colorControls()
        controls.inputImage = input
        switch scene {
        case .moon:
            controls.brightness = -0.025
            controls.contrast = 1.28
            controls.saturation = 0.88
        case .portrait:
            controls.brightness = 0.035; controls.contrast = 1.06; controls.saturation = 1.04
        case .food:
            controls.brightness = 0.045; controls.contrast = 1.10; controls.saturation = 1.12
        case .landscape:
            controls.brightness = 0.035; controls.contrast = 1.13; controls.saturation = 1.10
        case .vehicle:
            controls.brightness = 0.025; controls.contrast = 1.12; controls.saturation = 1.06
        case .document:
            controls.brightness = 0.04; controls.contrast = 1.18; controls.saturation = 0.90
        case .general:
            controls.brightness = 0.03; controls.contrast = 1.08; controls.saturation = 1.05
        }
        guard let colorAdjusted = controls.outputImage else { return image }
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = colorAdjusted
        exposure.ev = scene == .moon ? -0.65 : 0.18
        guard let exposed = exposure.outputImage else { return image }
        let finalImage: CIImage
        if scene == .moon {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = exposed
            sharpen.sharpness = 0.35
            finalImage = sharpen.outputImage ?? exposed
        } else { finalImage = exposed }
        guard let cgImage = context.createCGImage(finalImage, from: finalImage.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}