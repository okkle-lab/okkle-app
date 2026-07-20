import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct NativeInsightNarrative: Equatable {
  var headline: String
  var detail: String
  var summary: String
}

struct NativeInsightNarrativeContext: Equatable {
  var key: String
  var fallback: NativeInsightNarrative
  var prompt: String
}

enum NativeInsightNarrator {
  static func generate(context: NativeInsightNarrativeContext) async -> NativeInsightNarrative? {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      return await generateWithAppleIntelligence(context: context)
    }
#endif
    return nil
  }

#if canImport(FoundationModels)
  @available(iOS 26.0, *)
  private static func generateWithAppleIntelligence(context: NativeInsightNarrativeContext) async -> NativeInsightNarrative? {
    let model = SystemLanguageModel.default
    guard model.isAvailable, model.supportsLocale() else { return nil }

    let session = LanguageModelSession(
      model: model,
      instructions: """
      You write concise, trustworthy in-app insight copy for Okkle, a delivery-driver mileage and earnings app.
      Use only the supplied facts. Do not invent platforms, areas, money, tax advice, coordinates, or certainty.
      Keep the tone practical, calm, and encouraging. British English. No emoji.
      Return exactly three labelled lines: HEADLINE, DETAIL, SUMMARY.
      """
    )

    do {
      let response = try await session.respond(
        to: context.prompt,
        options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 160)
      )
      return parse(response.content, fallback: context.fallback)
    } catch {
      return nil
    }
  }
#endif

  private static func parse(_ output: String, fallback: NativeInsightNarrative) -> NativeInsightNarrative {
    var values: [String: String] = [:]
    for rawLine in output.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let separator = line.firstIndex(of: ":") else { continue }
      let key = line[..<separator].uppercased()
      let value = line[line.index(after: separator)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { continue }
      values[String(key)] = value
    }

    return NativeInsightNarrative(
      headline: clean(values["HEADLINE"], fallback: fallback.headline, maxCharacters: 58),
      detail: clean(values["DETAIL"], fallback: fallback.detail, maxCharacters: 130),
      summary: clean(values["SUMMARY"], fallback: fallback.summary, maxCharacters: 150)
    )
  }

  private static func clean(_ value: String?, fallback: String, maxCharacters: Int) -> String {
    guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      return fallback
    }
    text = text.replacingOccurrences(of: #"^["']|["']$"#, with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: "\n", with: " ")
    while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
    if text.count > maxCharacters {
      let index = text.index(text.startIndex, offsetBy: maxCharacters)
      text = String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
      if let lastSpace = text.lastIndex(of: " ") {
        text = String(text[..<lastSpace])
      }
      text += "..."
    }
    return text
  }
}
