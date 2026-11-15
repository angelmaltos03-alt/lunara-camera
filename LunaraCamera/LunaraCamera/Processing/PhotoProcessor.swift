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

    /// Still-photo entry point; it uses the same development graph as the Metal preview.
    func enhance(
        _ image: UIImage,
        scene: PhotoScene,
        mode: PhotoEditMode = .auto,
        look: PhotoLook = .natural,
        intensity: Double = 0.55,
        adjustments: PhotoAdjustments = PhotoAdjustments()
    ) -> UIImage {
        guard let input = CIImage(image: image) else { return image }
        let developed = develop(input, scene: scene, mode: mode, look: look, intensity: intensity, adjustments: adjustments)
        guard let cgImage = context.createCGImage(developed, from: input.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Shared Core Image graph: identical scene, AUTO/PRO, look and adjustment parameters for preview and stills.
    func develop(
        _ input: CIImage,
        scene: PhotoScene,
        mode: PhotoEditMode = .auto,
        look: PhotoLook = .natural,
        intensity: Double = 0.55,
        adjustments: PhotoAdjustments = PhotoAdjustments()
    ) -> CIImage {
        var baseExposure: Float = 0.08
        var baseBrightness: Float = 0.015
        var baseContrast: Float = 1.06
        var baseSaturation: Float = 1.04
        var baseVibrance: Float = 0.08
        var baseSharpness: Float = 0.12

        switch scene {
        case .moon:
            baseExposure = -0.55; baseBrightness = -0.015; baseContrast = 1.18
            baseSaturation = 0.90; baseVibrance = 0; baseSharpness = 0.35
        case .portrait:
            baseExposure = 0.10; baseBrightness = 0.018; baseContrast = 1.04
            baseSaturation = 1.04; baseVibrance = 0.12; baseSharpness = 0.10
        case .food:
            baseExposure = 0.12; baseBrightness = 0.025; baseContrast = 1.07
            baseSaturation = 1.08; baseVibrance = 0.18; baseSharpness = 0.14
        case .landscape:
            baseExposure = 0.08; baseBrightness = 0.015; baseContrast = 1.10
            baseSaturation = 1.07; baseVibrance = 0.16; baseSharpness = 0.18
        case .vehicle:
            baseExposure = 0.06; baseBrightness = 0.010; baseContrast = 1.09
            baseSaturation = 1.04; baseVibrance = 0.10; baseSharpness = 0.16
        case .document:
            baseExposure = 0.12; baseBrightness = 0.025; baseContrast = 1.16
            baseSaturation = 0.92; baseVibrance = 0; baseSharpness = 0.08
        case .general: break
        }

        let automaticStrength: Float = mode == .auto ? 1.0 : 0.55
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = input
        exposure.ev = baseExposure * automaticStrength + Float(adjustments.exposureEV)
        guard let exposed = exposure.outputImage else { return input }

        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = exposed
        vibrance.amount = baseVibrance * automaticStrength
        let vibranced = vibrance.outputImage ?? exposed

        let controls = CIFilter.colorControls()
        controls.inputImage = vibranced
        controls.brightness = baseBrightness * automaticStrength
        controls.contrast = 1 + (baseContrast - 1) * automaticStrength + Float(adjustments.contrast)
        controls.saturation = 1 + (baseSaturation - 1) * automaticStrength + Float(adjustments.saturation)
        guard let colorAdjusted = controls.outputImage else { return input }

        let temperature = CIFilter.temperatureAndTint()
        temperature.inputImage = colorAdjusted
        temperature.neutral = CIVector(x: 6500, y: 0)
        let warmShift = CGFloat(scene == .food ? 120 : 0) + CGFloat(adjustments.warmth * 1500)
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
        } else { blended = temperatureAdjusted }

        let sharpenAmount = min(max(baseSharpness * automaticStrength + Float(adjustments.sharpness), 0), 1)
        if sharpenAmount > 0.001 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = blended
            sharpen.sharpness = sharpenAmount
            return sharpen.outputImage?.cropped(to: input.extent) ?? blended
        }
        return blended
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


/// Local multi-frame lunar fusion. Frames are aligned to the sharpest reference that
/// Vision can register; if registration is unreliable, the best single frame is returned.
enum MoonStackProcessor {
    struct Result {
        let image: UIImage
        let inputFrameCount: Int
        let stackedFrameCount: Int
        let usedFallback: Bool
    }

    static func process(_ images: [UIImage]) -> Result {
        let usable = images.compactMap { image -> (UIImage, CGImage)? in
            guard let cgImage = image.cgImage else { return nil }
            return (image, cgImage)
        }
        guard let first = usable.first else {
            return Result(image: UIImage(), inputFrameCount: images.count, stackedFrameCount: 0, usedFallback: true)
        }
        guard usable.count > 1 else {
            return Result(image: first.0, inputFrameCount: images.count, stackedFrameCount: usable.count, usedFallback: true)
        }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        let ranked = usable.map { pair -> (UIImage, CGImage, Double) in
            (pair.0, pair.1, sharpnessScore(pair.1, context: context))
        }.sorted { $0.2 > $1.2 }

        guard let reference = ranked.first,
              reference.2 > 0.0001 else {
            return Result(image: ranked[0].0, inputFrameCount: images.count, stackedFrameCount: 1, usedFallback: true)
        }

        let referenceImage = CIImage(cgImage: reference.1)
        let extent = referenceImage.extent
        var aligned = [referenceImage]
        for candidate in ranked.dropFirst() {
            let request = VNTranslationalImageRegistrationRequest(targetedCGImage: reference.1)
            do {
                try VNImageRequestHandler(cgImage: candidate.1).perform([request])
                guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else { continue }
                let transform = observation.alignmentTransform
                // Reject extreme shifts; those are more likely unrelated framing or bad registration.
                guard abs(transform.tx) < extent.width * 0.12,
                      abs(transform.ty) < extent.height * 0.12 else { continue }
                let transformed = CIImage(cgImage: candidate.1).transformed(by: transform)
                aligned.append(transformed.cropped(to: extent))
            } catch {
                continue
            }
        }

        guard aligned.count >= 2 else {
            return Result(image: reference.0, inputFrameCount: images.count, stackedFrameCount: 1, usedFallback: true)
        }

        let weight = CGFloat(1.0 / Double(aligned.count))
        let vector = CIVector(x: weight, y: 0, z: 0, w: 0)
        let alpha = CIVector(x: 0, y: 0, z: 0, w: weight)
        var sum: CIImage?
        for frame in aligned {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = frame
            matrix.rVector = vector
            matrix.gVector = CIVector(x: 0, y: weight, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: weight, w: 0)
            matrix.aVector = alpha
            guard let weighted = matrix.outputImage?.cropped(to: extent) else { continue }
            if let current = sum {
                let addition = CIFilter(name: "CIAdditionCompositing")
                addition?.setValue(weighted, forKey: kCIInputImageKey)
                addition?.setValue(current, forKey: kCIInputBackgroundImageKey)
                sum = addition?.outputImage?.cropped(to: extent) ?? current
            } else {
                sum = weighted
            }
        }

        guard let fused = sum,
              let output = context.createCGImage(fused, from: extent) else {
            return Result(image: reference.0, inputFrameCount: images.count, stackedFrameCount: 1, usedFallback: true)
        }
        return Result(
            image: UIImage(cgImage: output, scale: reference.0.scale, orientation: reference.0.imageOrientation),
            inputFrameCount: images.count,
            stackedFrameCount: aligned.count,
            usedFallback: false
        )
    }

    private static func sharpnessScore(_ image: CGImage, context: CIContext) -> Double {
        let source = CIImage(cgImage: image)
        let edges = CIFilter.edges()
        edges.inputImage = source
        edges.intensity = 1.0
        guard let edgeImage = edges.outputImage else { return 0 }
        let average = CIFilter.areaAverage()
        average.inputImage = edgeImage
        average.extent = source.extent
        guard let output = average.outputImage else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3.0 * 255.0)
    }
}
