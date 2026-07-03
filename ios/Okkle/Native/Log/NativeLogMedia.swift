import Foundation
import SwiftUI
import UIKit

struct NativeReceiptScanResult {
  var amount: Double?
  var category: String?
  var merchant: String?

  var hasValues: Bool {
    amount != nil || category != nil || merchant != nil
  }

  var summary: String {
    var parts: [String] = []
    if let amount {
      parts.append(gbp(amount))
    }
    if let category {
      parts.append(category)
    }
    if let merchant {
      parts.append(merchant)
    }
    return parts.isEmpty ? "Receipt scanned." : "Filled \(parts.joined(separator: " · "))."
  }
}

func nativeParseReceipt(lines: [String]) -> NativeReceiptScanResult {
  let cleaned = lines
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  let text = cleaned.joined(separator: "\n")
  return NativeReceiptScanResult(
    amount: nativeReceiptAmount(from: text),
    category: nativeReceiptCategory(from: text),
    merchant: nativeReceiptMerchant(from: cleaned)
  )
}

func nativeReceiptAmount(from text: String) -> Double? {
  let pattern = #"(?i)(?:total|amount|paid|balance|card|sale)?[^\d£$]{0,12}[£$]?\s*(\d{1,4}[.,]\d{2})"#
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
  let nsText = text as NSString
  let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
  let scored = matches.compactMap { match -> (score: Int, value: Double)? in
    guard match.numberOfRanges > 1 else { return nil }
    let matchText = nsText.substring(with: match.range(at: 0)).lowercased()
    let numberText = nsText.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
    guard let value = Double(numberText), value > 0 else { return nil }
    var score = 0
    if matchText.contains("total") { score += 4 }
    if matchText.contains("amount") || matchText.contains("paid") || matchText.contains("card") { score += 2 }
    if matchText.contains("subtotal") || matchText.contains("change") || matchText.contains("vat") { score -= 3 }
    return (score, value)
  }
  return scored.sorted { left, right in
    if left.score == right.score { return left.value > right.value }
    return left.score > right.score
  }.first?.value
}

func nativeReceiptCategory(from text: String) -> String? {
  let lower = text.lowercased()
  let checks: [(String, [String])] = [
    ("Fuel", ["fuel", "petrol", "diesel", "shell", "bp", "esso", "texaco", "jet ", "gulf"]),
    ("Charging", ["ev charge", "charging", "chargepoint", "instavolt", "pod point", "tesla supercharger"]),
    ("Parking", ["parking", "parkmobile", "ringgo", "paybyphone"]),
    ("Phone", ["vodafone", "ee ", "o2", "three", "giffgaff", "mobile", "phone"]),
    ("Insurance", ["insurance", "insurer", "policy"]),
    ("Maintenance / repairs", ["repair", "service", "garage", "mot", "maintenance"]),
    ("Tyres", ["tyre", "tire", "kwik fit", "national tyres"]),
    ("Congestion charge", ["congestion"]),
    ("ULEZ charge", ["ulez", "clean air zone", "caz"]),
    ("Insulated bag", ["insulated bag", "thermal bag"]),
    ("Helmet / safety", ["helmet", "hi-vis", "safety"]),
    ("App subscription", ["subscription", "app store", "google play"])
  ]
  return checks.first { _, keywords in keywords.contains { lower.contains($0) } }?.0
}

func nativeReceiptMerchant(from lines: [String]) -> String? {
  let ignored = ["receipt", "invoice", "tax", "vat", "total", "amount", "card", "visa", "mastercard", "auth", "date", "time"]
  for line in lines.prefix(8) {
    let clean = line
      .replacingOccurrences(of: #"[^A-Za-z0-9 '&.-]"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = clean.lowercased()
    guard clean.count >= 2, clean.count <= 34 else { continue }
    guard !ignored.contains(where: { lower.contains($0) }) else { continue }
    guard clean.rangeOfCharacter(from: .letters) != nil else { continue }
    return clean.capitalized
  }
  return nil
}

func nativeOptimizedReceiptData(image: UIImage?, data: Data?) -> Data? {
  guard let image = image ?? data.flatMap(UIImage.init(data:)) else {
    return data
  }

  let maxDimension: CGFloat = 1_600
  let longestSide = max(image.size.width, image.size.height)
  guard longestSide > 0 else { return data }

  let scale = min(1, maxDimension / longestSide)
  let outputImage: UIImage
  if scale < 1 {
    let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    outputImage = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: newSize))
    }
  } else {
    outputImage = image
  }

  return outputImage.jpegData(compressionQuality: 0.78) ?? data
}

func uniqueStrings(_ values: [String]) -> [String] {
  var seen = Set<String>()
  return values.compactMap { value in
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    let key = clean.lowercased()
    guard !seen.contains(key) else { return nil }
    seen.insert(key)
    return clean
  }
}

struct NativeCameraPicker: UIViewControllerRepresentable {
  @Binding var image: UIImage?
  @Binding var imageData: Data?
  @Environment(\.dismiss) private var dismiss

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let parent: NativeCameraPicker

    init(_ parent: NativeCameraPicker) {
      self.parent = parent
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      let picked = info[.originalImage] as? UIImage
      parent.image = picked
      parent.imageData = picked?.jpegData(compressionQuality: 0.72)
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}
