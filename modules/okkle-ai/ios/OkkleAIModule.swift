import ExpoModulesCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Apple Intelligence on-device LLM (iOS 26 Foundation Models). Lets us extract
// structured data from receipt/earnings text far more robustly than keyword
// heuristics — and entirely on-device, nothing uploaded. Degrades gracefully on
// devices/OS without Apple Intelligence (isAvailable -> false).
public class OkkleAIModule: Module {
  private var modelAvailable: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      switch SystemLanguageModel.default.availability {
      case .available: return true
      default: return false
      }
    }
    #endif
    return false
  }

  public func definition() -> ModuleDefinition {
    Name("OkkleAI")

    Function("isAvailable") { () -> Bool in
      return self.modelAvailable
    }

    // Run a one-shot prompt with system instructions; resolves the model's text.
    AsyncFunction("respond") { (instructions: String, prompt: String, promise: Promise) in
      #if canImport(FoundationModels)
      if #available(iOS 26.0, *), self.modelAvailable {
        Task {
          do {
            let session = LanguageModelSession(instructions: instructions)
            let result = try await session.respond(to: prompt)
            promise.resolve(["available": true, "text": result.content])
          } catch {
            promise.resolve(["available": true, "text": "", "error": error.localizedDescription])
          }
        }
        return
      }
      #endif
      promise.resolve(["available": false, "text": ""])
    }
  }
}
