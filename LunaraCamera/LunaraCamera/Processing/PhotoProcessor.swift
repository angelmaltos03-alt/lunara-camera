import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum PhotoEditMode: String, CaseIterable, Identifiable {
    case auto
    case pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "AUTO"
        case .pro: "PRO"
        }
    }
}

enum PhotoLook: String, CaseIterable, Identifiable {
    case natural
    case vivid
    case warm
    case cool
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "Natural"
        case .vivid: "Vivid"
        case .warm: "Cálido"
        case .cool: "Frío"
        case .mono: "Mono"
        }
    }
}

struct PhotoAdjustments: Equatable {
    var exposureEV: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0
    var sharpness: Double = 0
}

struct PhotoProcessor {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Develops the original capture at full resolution. The same pipeline is
    /// used whenever the user changes a PRO control, avoiding destructive edits.
    func enhance(
        _ image: UIImage,
        scene: PhotoScene,
        mode: PhotoEditMode = .auto,
        look: PhotoLook = .natural,
        intensity: Double = 0.55,
        adjustments: PhotoAdjustments = PhotoAdjustments()
    ) -> UIImage {
        guard let input = CIImage(image: image) else { return image }

        var baseExposure: Float = 0.08
        var baseBrightness: Float = 0.015
        var baseContrast: Float = 1.06
        var baseSaturation: Float = 1.04
        var baseVibrance: Float = 0.08
        var baseSharpness: Float = 0.12

        switch scene {
        case .moon:
            baseExposure = -0.55
            baseBrightness = -0.015
            baseContrast = 1.18
            baseSaturation = 0.90
            baseVibrance = 0
            baseSharpness = 0.35
        case .portrait:
            baseExposure = 0.10
            baseBrightness = 0.018
            baseContrast = 1.04
            baseSaturation = 1.04
            baseVibrance = 0.12
            baseSharpness = 0.10
        case .food:
            baseExposure = 0.12
            baseBrightness = 0.025
            baseContrast = 1.07
            baseSaturation = 1.08
            baseVibrance = 0.18
            baseSharpness = 0.14
        case .landscape:
            baseExposure = 0.08
            baseBrightness = 0.015
            baseContrast = 1.10
            baseSaturation = 1.07
            baseVibrance = 0.16
            baseSharpness = 0.18
        case .vehicle:
            baseExposure = 0.06
            baseBrightness = 0.010
            baseContrast = 1.09
            baseSaturation = 1.04
            baseVibrance = 0.10
            baseSharpness = 0.16
        case .document:
            baseExposure = 0.12
            baseBrightness = 0.025
            baseContrast = 1.16
            baseSaturation = 0.92
            baseVibrance = 0
            baseSharpness = 0.08
        case .general:
            break
        }

        // AUTO applies the full scene recommendation. PRO keeps a gentler
        // automatic baseline and lets the photographer take over.
        let automaticStrength: Float = mode == .auto ? 1.0 : 0.55
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = input
        exposure.ev = baseExposure * automaticStrength + Float(adjustments.exposureEV)
        guard let exposed = exposure.outputImage else { return image }

        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = exposed
        vibrance.amount = baseVibrance * automaticStrength
        let vibranced = vibrance.outputImage ?? exposed

        let controls = CIFilter.colorControls()
        controls.inputImage = vibranced
        controls.brightness = baseBrightness * automaticStrength
        controls.contrast = 1 + (baseContrast - 1) * automaticStrength + Float(adjustments.contrast)
        controls.saturation = 1 + (baseSaturation - 1) * automaticStrength + Float(adjustments.saturation)
        guard let colorAdjusted = controls.outputImage else { return image }

        let temperature = CIFilter.temperatureAndTint()
        temperature.inputImage = colorAdjusted
        temperature.neutral = CIVector(x: 6500, y: 0)
        let warmShift = (scene == .food ? 120 : 0) + adjustments.warmth * 1500
        temperature.targetNeutral = CIVector(x: 6500 - warmShift, y: 0)
        let temperatureAdjusted = temperature.outputImage ?? colorAdjusted

        let styled = apply(look: look, to: temperatureAdjusted)
        let amount = look == .natural ? 0 : Float(min(max(intensity, 0), 1))
        let blended: CIImage
        if amount > 0 {
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = temperatureAdjusted
            dissolve.targetImage = styled
            dissolve.time = amount
            blended = dissolve.outputImage?.cropped(to: input.extent) ?? styled
        } else {
            blended = temperatureAdjusted
        }

        let sharpenAmount = min(max(baseSharpness * automaticStrength + Float(adjustments.sharpness), 0), 1)
        let finalImage: CIImage
        if sharpenAmount > 0.001 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = blended
            sharpen.sharpness = sharpenAmount
            finalImage = sharpen.outputImage?.cropped(to: input.extent) ?? blended
        } else {
            finalImage = blended
        }

        guard let cgImage = context.createCGImage(finalImage, from: input.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func apply(look: PhotoLook, to image: CIImage) -> CIImage {
        switch look {
        case .natural:
            return image
        case .vivid:
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = image
            vibrance.amount = 0.65
            let controls = CIFilter.colorControls()
            controls.inputImage = vibrance.outputImage ?? image
            controls.saturation = 1.16
            controls.contrast = 1.06
            return controls.outputImage ?? image
        case .warm, .cool:
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = image
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: look == .warm ? 4700 : 9000, y: 0)
            return temperature.outputImage ?? image
        case .mono:
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = image
            return mono.outputImage ?? image
        }
    }
}
