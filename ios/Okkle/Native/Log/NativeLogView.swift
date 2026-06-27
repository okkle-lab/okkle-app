import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
struct NativeLogView: View {
  @EnvironmentObject private var store: OkkleStore
  @Binding var selectedTab: NativeTab
  @State private var kind: NativeLogKind = .income
  @State private var amount = ""
  @State private var distance = ""
  @State private var category = ""
  @State private var merchant = ""
  @State private var platform = "Uber Eats"
  @State private var vehicle: NativeVehicle = .car
  @State private var period: NativePayPeriod = .day
  @State private var date = Date()
  @State private var receiptItem: PhotosPickerItem?
  @State private var receiptImage: UIImage?
  @State private var receiptData: Data?
  @State private var receiptScanMessage = "Add a receipt and Okkle will try to fill the expense details."
  @State private var receiptScanning = false
  @State private var showCamera = false
  @State private var savedRecord: NativeRecord?
  @FocusState private var focused: LogField?

  private enum LogField {
    case amount
    case miles
    case category
    case merchant
  }

  var body: some View {
    NativeScreen(title: "Log", subtitle: "Add earnings, expenses and manual mileage.") {
      NativeGlassCard {
        VStack(alignment: .leading, spacing: 16) {
          Picker("Record type", selection: $kind) {
            ForEach(NativeLogKind.allCases) { item in
              Label(item.label, systemImage: item.symbol).tag(item)
            }
          }
          .pickerStyle(.segmented)
          .onChange(of: kind) { _ in resetEntry(keepKind: true) }

          if kind == .expense {
            receiptBetaPanel
          }

          if kind == .mileage {
            nativeNumberField(title: "Miles", text: $distance, placeholder: "0.0", field: .miles)
            Picker("Vehicle", selection: $vehicle) {
              ForEach(NativeVehicle.allCases) { item in
                Label(item.label, systemImage: item.symbol).tag(item)
              }
            }
          } else {
            nativeNumberField(title: "Amount", text: $amount, placeholder: "0.00", field: .amount)
          }

          if kind == .income {
            Picker("Platform", selection: $platform) {
              ForEach(store.settings.platforms, id: \.self) { Text($0).tag($0) }
            }
          }

          if kind == .expense {
            NativeFreeTextDropdown(
              title: "Category",
              placeholder: "Choose or type a category",
              options: categoryOptions,
              text: $category
            )
            NativeFreeTextDropdown(
              title: "Merchant",
              placeholder: "Choose or type a merchant",
              options: merchantOptions,
              text: $merchant
            )
          }

          Picker("Period", selection: $period) {
            ForEach(NativePayPeriod.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)

          DatePicker("Date", selection: $date, displayedComponents: .date)
            .datePickerStyle(.compact)

          Button(action: saveRecord) {
            Label("Submit", systemImage: "arrow.right.circle.fill")
              .font(.system(size: 17, weight: .bold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
          }
          .buttonStyle(.borderedProminent)
          .tint(OkkleColor.brand)
          .disabled(!canSave)
        }
      }
    }
    .sheet(isPresented: $showCamera) {
      NativeCameraPicker(image: $receiptImage, imageData: $receiptData)
        .ignoresSafeArea()
    }
    .task(id: receiptItem) {
      guard let receiptItem, let data = try? await receiptItem.loadTransferable(type: Data.self) else { return }
      receiptData = data
      receiptImage = UIImage(data: data)
    }
    .onChange(of: receiptData) { data in
      guard let data else { return }
      scanReceipt(data)
    }
    .alert("Saved to records", isPresented: Binding(get: { savedRecord != nil }, set: { if !$0 { savedRecord = nil } })) {
      Button("View records") {
        resetEntry()
        savedRecord = nil
        selectedTab = .records
      }
    } message: {
      Text(savedMessage)
    }
    .nativeKeyboardDoneToolbar()
  }

  private var canSave: Bool {
    switch kind {
    case .mileage:
      return Double(distance) ?? 0 > 0
    case .income:
      return Double(amount) ?? 0 > 0
    case .expense:
      return (Double(amount) ?? 0 > 0) && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var categoryOptions: [String] {
    let recent = store.records
      .filter { $0.kind == .expense }
      .compactMap { $0.category }
    return uniqueStrings(recent + nativeExpenseCategories)
  }

  private var merchantOptions: [String] {
    let recent = store.records
      .filter { $0.kind == .expense }
      .compactMap { $0.merchant }
    return uniqueStrings(recent)
  }

  private var savedMessage: String {
    guard let savedRecord else { return "" }
    switch savedRecord.kind {
    case .mileage:
      return "\(miles(savedRecord.miles ?? 0)) saved with \(gbp(savedRecord.deduction ?? 0, whole: true)) deduction."
    case .income:
      return "\(gbp(savedRecord.amount ?? 0)) earnings saved."
    case .expense:
      return "\(gbp(savedRecord.amount ?? 0)) expense saved."
    }
  }

  private var receiptBetaPanel: some View {
    NativeAiCard {
      ZStack(alignment: .topTrailing) {
        VStack(alignment: .leading, spacing: 12) {
          Label("Receipt scan", systemImage: "wand.and.stars")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(OkkleColor.brandDark)
            .padding(.trailing, 74)
          Text(receiptScanning ? "Scanning receipt..." : receiptScanMessage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .padding(.trailing, 8)

          HStack(spacing: 10) {
            PhotosPicker(selection: $receiptItem, matching: .images) {
              Label("Choose photo", systemImage: "photo")
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(OkkleColor.brand)

            Button {
              showCamera = true
            } label: {
              Label("Camera", systemImage: "camera")
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
          }

          if let receiptImage {
            Image(uiImage: receiptImage)
              .resizable()
              .scaledToFill()
              .frame(height: 130)
              .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
        }

        Text("BETA")
          .font(.system(size: 11, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(.purple, in: Capsule())
          .shadow(color: .purple.opacity(0.28), radius: 12, y: 6)
      }
    }
  }

  private func scanReceipt(_ data: Data) {
    guard kind == .expense, let image = UIImage(data: data), let cgImage = image.cgImage else { return }
    receiptScanning = true
    receiptScanMessage = "Scanning receipt..."

    let request = VNRecognizeTextRequest { request, error in
      let observations = request.results as? [VNRecognizedTextObservation] ?? []
      let lines = observations.compactMap { $0.topCandidates(1).first?.string }
      let parsed = nativeParseReceipt(lines: lines)

      DispatchQueue.main.async {
        receiptScanning = false
        applyReceiptScan(parsed)
        if parsed.hasValues {
          receiptScanMessage = parsed.summary
        } else if let error {
          receiptScanMessage = "Could not scan this receipt. \(error.localizedDescription)"
        } else {
          receiptScanMessage = "Could not confidently read amount, category or merchant. You can still enter them manually."
        }
      }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
      } catch {
        DispatchQueue.main.async {
          receiptScanning = false
          receiptScanMessage = "Could not scan this receipt. \(error.localizedDescription)"
        }
      }
    }
  }

  private func applyReceiptScan(_ result: NativeReceiptScanResult) {
    if amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedAmount = result.amount {
      amount = String(format: "%.2f", parsedAmount)
    }
    if category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedCategory = result.category {
      category = parsedCategory
    }
    if merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedMerchant = result.merchant {
      merchant = parsedMerchant
    }
  }

  private func nativeNumberField(title: String, text: Binding<String>, placeholder: String, field: LogField) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
      TextField(placeholder, text: text)
        .keyboardType(.decimalPad)
        .submitLabel(.done)
        .focused($focused, equals: field)
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .padding(14)
        .background(OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 18))
    }
  }

  private func saveRecord() {
    let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
    let bounds = store.periodBounds(for: date, period: period)
    let record: NativeRecord
    switch kind {
    case .mileage:
      let milesValue = Double(distance) ?? 0
      record = NativeRecord(
        kind: .mileage,
        platform: nil,
        vehicle: vehicle,
        amount: nil,
        miles: milesValue,
        deduction: store.calcDeduction(miles: milesValue, vehicle: vehicle, date: date),
        category: nil,
        merchant: nil,
        date: date,
        period: period,
        periodStart: bounds.start,
        periodEnd: bounds.end,
        receiptImageData: nil
      )
    case .income:
      record = NativeRecord(
        kind: .income,
        platform: platform,
        vehicle: nil,
        amount: Double(amount) ?? 0,
        miles: nil,
        deduction: nil,
        category: nil,
        merchant: nil,
        date: date,
        period: period,
        periodStart: bounds.start,
        periodEnd: bounds.end,
        receiptImageData: receiptData
      )
    case .expense:
      record = NativeRecord(
        kind: .expense,
        platform: nil,
        vehicle: nil,
        amount: Double(amount) ?? 0,
        miles: nil,
        deduction: nil,
        category: cleanCategory,
        merchant: cleanMerchant.isEmpty ? nil : cleanMerchant,
        date: date,
        period: period,
        periodStart: bounds.start,
        periodEnd: bounds.end,
        receiptImageData: receiptData
      )
    }
    store.addRecord(record)
    savedRecord = record
  }

  private func resetEntry(keepKind: Bool = false) {
    if !keepKind { kind = .income }
    amount = ""
    distance = ""
    category = ""
    merchant = ""
    vehicle = store.settings.defaultVehicle
    platform = store.settings.platforms.first ?? "Uber Eats"
    period = .day
    date = Date()
    receiptImage = nil
    receiptData = nil
    receiptItem = nil
    receiptScanMessage = "Add a receipt and Okkle will try to fill the expense details."
    receiptScanning = false
  }
}

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
