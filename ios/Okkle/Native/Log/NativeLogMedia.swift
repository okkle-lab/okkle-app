import Foundation
import SwiftUI
import UIKit

struct NativeReceiptScanResult {
  var amount: Double?
  var date: Date?
  var category: String?
  var merchant: String?

  var hasValues: Bool {
    amount != nil || date != nil || category != nil || merchant != nil
  }

  var summary: String {
    var parts: [String] = []
    if let amount {
      parts.append(gbp(amount))
    }
    if let date {
      parts.append(date.formatted(date: .abbreviated, time: .omitted))
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

enum NativeReceiptDateOrder: Equatable {
  case dayMonthYear
  case monthDayYear
}

func nativeParseReceipt(
  lines: [String],
  dateOrder: NativeReceiptDateOrder = .dayMonthYear,
  referenceDate: Date = Date(),
  calendar: Calendar = .current
) -> NativeReceiptScanResult {
  let cleaned = lines
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  let text = cleaned.joined(separator: "\n")
  return NativeReceiptScanResult(
    amount: nativeReceiptAmount(from: text),
    date: nativeReceiptDate(
      from: cleaned,
      dateOrder: dateOrder,
      referenceDate: referenceDate,
      calendar: calendar
    ),
    category: nativeReceiptCategory(from: text),
    merchant: nativeReceiptMerchant(from: cleaned)
  )
}

func nativeReceiptAmount(from text: String) -> Double? {
  let pattern = #"(?i)(?:total|amount|paid|balance|card|sale)?[^\d£$]{0,12}[£$]?\s*((?:\d{1,3}(?:[.,\s]\d{3})+|\d{1,6})[.,]\d{2})\b"#
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
  let nsText = text as NSString
  let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
  let scored = matches.compactMap { match -> (score: Int, value: Double)? in
    guard match.numberOfRanges > 1 else { return nil }
    let matchText = nsText.substring(with: match.range(at: 0)).lowercased()
    let numberRange = match.range(at: 1)
    let trailingText = nsText.substring(from: NSMaxRange(numberRange))
    // A dotted receipt date such as 21.07.2026 must not become a £21.07
    // amount when the OCR text contains no stronger monetary candidate.
    if trailingText.range(of: #"^[./-]\d{2,4}"#, options: .regularExpression) != nil {
      return nil
    }
    let rawNumber = nsText.substring(with: numberRange)
    guard let decimalSeparator = rawNumber.lastIndex(where: { $0 == "." || $0 == "," }) else { return nil }
    let whole = rawNumber[..<decimalSeparator]
      .filter { $0.isNumber }
    let fraction = rawNumber[rawNumber.index(after: decimalSeparator)...]
      .filter { $0.isNumber }
    let numberText = "\(whole).\(fraction)"
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

func nativeReceiptDate(
  from lines: [String],
  dateOrder: NativeReceiptDateOrder,
  referenceDate: Date = Date(),
  calendar: Calendar = .current
) -> Date? {
  struct Candidate {
    let date: Date
    let score: Int
    let lineIndex: Int
  }

  let months: [String: Int] = [
    "jan": 1, "january": 1,
    "feb": 2, "february": 2,
    "mar": 3, "march": 3,
    "apr": 4, "april": 4,
    "may": 5,
    "jun": 6, "june": 6,
    "jul": 7, "july": 7,
    "aug": 8, "august": 8,
    "sep": 9, "sept": 9, "september": 9,
    "oct": 10, "october": 10,
    "nov": 11, "november": 11,
    "dec": 12, "december": 12
  ]
  let monthPattern = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
  let patterns: [(String, Int, (NSTextCheckingResult, NSString) -> (Int, Int, Int)?)] = [
    (#"\b((?:19|20)\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b"#, 4, { match, text in
      guard match.numberOfRanges == 4 else { return nil }
      return (
        Int(text.substring(with: match.range(at: 1))) ?? 0,
        Int(text.substring(with: match.range(at: 2))) ?? 0,
        Int(text.substring(with: match.range(at: 3))) ?? 0
      )
    }),
    (#"\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b"#, 2, { match, text in
      guard match.numberOfRanges == 4 else { return nil }
      let first = Int(text.substring(with: match.range(at: 1))) ?? 0
      let second = Int(text.substring(with: match.range(at: 2))) ?? 0
      var year = Int(text.substring(with: match.range(at: 3))) ?? 0
      if year < 100 { year += 2_000 }
      let day: Int
      let month: Int
      if first > 12 {
        day = first
        month = second
      } else if second > 12 {
        day = second
        month = first
      } else if dateOrder == .monthDayYear {
        day = second
        month = first
      } else {
        day = first
        month = second
      }
      return (year, month, day)
    }),
    (#"(?i)\b(\d{1,2})(?:st|nd|rd|th)?[\s./-]+("# + monthPattern + #")[\s,./-]+(\d{2,4})\b"#, 4, { match, text in
      guard match.numberOfRanges == 4 else { return nil }
      var year = Int(text.substring(with: match.range(at: 3))) ?? 0
      if year < 100 { year += 2_000 }
      let monthName = text.substring(with: match.range(at: 2)).lowercased()
      return (year, months[monthName] ?? 0, Int(text.substring(with: match.range(at: 1))) ?? 0)
    }),
    (#"(?i)\b("# + monthPattern + #")[\s./-]+(\d{1,2})(?:st|nd|rd|th)?(?:,)?[\s./-]+(\d{2,4})\b"#, 4, { match, text in
      guard match.numberOfRanges == 4 else { return nil }
      var year = Int(text.substring(with: match.range(at: 3))) ?? 0
      if year < 100 { year += 2_000 }
      let monthName = text.substring(with: match.range(at: 1)).lowercased()
      return (year, months[monthName] ?? 0, Int(text.substring(with: match.range(at: 2))) ?? 0)
    })
  ]

  let earliestAllowed = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .distantPast
  let latestAllowed = calendar.date(byAdding: .day, value: 2, to: referenceDate) ?? referenceDate
  var candidates: [Candidate] = []

  for (lineIndex, line) in lines.enumerated() {
    let lower = line.lowercased()
    if ["expiry", "expires", "expiration", "valid thru", "valid until", "due date"]
      .contains(where: { lower.contains($0) }) {
      continue
    }
    var contextScore = max(0, 4 - lineIndex / 2)
    if lower.contains("transaction date") || lower.contains("purchase date") {
      contextScore += 9
    } else if ["date", "dated", "paid on", "purchased", "issued", "order placed"]
      .contains(where: { lower.contains($0) }) {
      contextScore += 6
    }

    let nsLine = line as NSString
    for (pattern, formatScore, components) in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      for match in regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
        guard let (year, month, day) = components(match, nsLine),
              year >= 2000,
              let parsed = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
        let verified = calendar.dateComponents([.year, .month, .day], from: parsed)
        guard verified.year == year,
              verified.month == month,
              verified.day == day,
              parsed >= earliestAllowed,
              parsed <= latestAllowed else { continue }
        candidates.append(Candidate(date: parsed, score: contextScore + formatScore, lineIndex: lineIndex))
      }
    }
  }

  return candidates.sorted {
    if $0.score == $1.score { return $0.lineIndex < $1.lineIndex }
    return $0.score > $1.score
  }.first?.date
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
