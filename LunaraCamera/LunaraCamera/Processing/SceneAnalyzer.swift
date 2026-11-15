import Vision
import UIKit

enum PhotoScene: String {
    case moon = "Luna"
    case portrait = "Retrato"
    case food = "Comida"
    case landscape = "Paisaje"
    case vehicle = "Automóvil"
    case document = "Documento"
    case general = "General"
}

struct SceneAnalyzer {
    func detect(in image: UIImage) -> PhotoScene {
        guard let cgImage = image.cgImage else { return .general }
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let labels = (request.results ?? []).prefix(8).map { $0.identifier.lowercased() }
            let text = labels.joined(separator: " ")
            if containsAny(text, ["moon", "full moon", "lunar", "crescent moon"]) { return .moon }
            if containsAny(text, ["food", "dish", "meal", "fruit", "vegetable"]) { return .food }
            if containsAny(text, ["person", "face", "portrait", "man", "woman"]) { return .portrait }
            if containsAny(text, ["car", "vehicle", "truck", "motorcycle", "automobile"]) { return .vehicle }
            if containsAny(text, ["landscape", "tree", "mountain", "sky", "plant", "forest"]) { return .landscape }
            if containsAny(text, ["document", "text", "paper", "book"]) { return .document }
        } catch { }
        return .general
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }
}