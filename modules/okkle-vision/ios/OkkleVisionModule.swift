import ExpoModulesCore
import Vision
import UIKit

// On-device receipt OCR via Apple's Vision framework. Reads the text off a
// receipt photo locally — nothing is uploaded, no AI service, no cost.
public class OkkleVisionModule: Module {
  public func definition() -> ModuleDefinition {
    Name("OkkleVision")

    Function("isAvailable") { () -> Bool in
      return true
    }

    // Recognize text in the image at `uri` (a file:// path from the image picker).
    // Resolves { available: Bool, lines: [String] } — top text candidates, in order.
    AsyncFunction("recognizeText") { (uri: String, promise: Promise) in
      let url: URL? = uri.hasPrefix("file://") ? URL(string: uri) : URL(fileURLWithPath: uri)
      guard let url = url,
            let data = try? Data(contentsOf: url),
            let image = UIImage(data: data),
            let cgImage = image.cgImage else {
        promise.resolve(["available": true, "lines": [String]()])
        return
      }

      let request = VNRecognizeTextRequest { req, error in
        guard error == nil,
              let observations = req.results as? [VNRecognizedTextObservation] else {
          promise.resolve(["available": true, "lines": [String]()])
          return
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        promise.resolve(["available": true, "lines": lines])
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true

      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try handler.perform([request])
        } catch {
          promise.resolve(["available": true, "lines": [String]()])
        }
      }
    }
  }
}
