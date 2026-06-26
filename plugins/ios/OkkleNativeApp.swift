import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UIKit

private enum OkkleColor {
  static let brand = Color(red: 0.03, green: 0.58, blue: 0.49)
  static let brandDark = Color(red: 0.03, green: 0.36, blue: 0.31)
  static let mint = Color(red: 0.83, green: 0.97, blue: 0.94)
  static let ink = Color(red: 0.10, green: 0.16, blue: 0.14)
  static let muted = Color(red: 0.43, green: 0.49, blue: 0.46)
  static let line = Color.black.opacity(0.08)
  static let amber = Color(red: 0.86, green: 0.50, blue: 0.08)
  static let red = Color(red: 0.82, green: 0.20, blue: 0.18)
  static let blue = Color(red: 0.18, green: 0.39, blue: 0.86)
}

private let gbpFormatter: NumberFormatter = {
  let formatter = NumberFormatter()
  formatter.numberStyle = .currency
  formatter.currencyCode = "GBP"
  formatter.maximumFractionDigits = 2
  formatter.minimumFractionDigits = 2
  return formatter
}()

private let wholeGbpFormatter: NumberFormatter = {
  let formatter = NumberFormatter()
  formatter.numberStyle = .currency
  formatter.currencyCode = "GBP"
  formatter.maximumFractionDigits = 0
  formatter.minimumFractionDigits = 0
  return formatter
}()

private func gbp(_ value: Double, whole: Bool = false) -> String {
  let formatter = whole ? wholeGbpFormatter : gbpFormatter
  return formatter.string(from: NSNumber(value: value)) ?? "GBP \(value)"
}

private func miles(_ value: Double) -> String {
  value >= 1_000 ? "\(Int(value.rounded()).formatted()) mi" : String(format: "%.1f mi", value)
}

private func shortDate(_ date: Date) -> String {
  date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}

private func monthLabel(_ date: Date) -> String {
  date.formatted(.dateTime.month(.abbreviated).year())
}

private func hideKeyboard() {
  UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

enum NativeVehicle: String, CaseIterable, Identifiable, Codable {
  case car
  case motorbike
  case bike
  case van

  var id: String { rawValue }

  var label: String {
    switch self {
    case .car: return "Car"
    case .motorbike: return "Motorbike"
    case .bike: return "E-bike / Bicycle"
    case .van: return "Van"
    }
  }

  var symbol: String {
    switch self {
    case .car: return "car.fill"
    case .motorbike: return "scooter"
    case .bike: return "bicycle"
    case .van: return "shippingbox.fill"
    }
  }

  func rateBand(on date: Date) -> (first: Double, after: Double) {
    let isNewRate = Calendar.current.compare(date, to: DateComponents(calendar: .current, year: 2026, month: 4, day: 6).date ?? date, toGranularity: .day) != .orderedAscending
    switch self {
    case .car, .van:
      return (isNewRate ? 0.55 : 0.45, 0.25)
    case .motorbike:
      return (0.24, 0.24)
    case .bike:
      return (0.20, 0.20)
    }
  }
}

enum NativeRegion: String, CaseIterable, Identifiable, Codable {
  case ruk
  case scotland

  var id: String { rawValue }

  var label: String {
    switch self {
    case .ruk: return "England, Wales or NI"
    case .scotland: return "Scotland"
    }
  }
}

enum NativeLogKind: String, CaseIterable, Identifiable, Codable {
  case income
  case expense
  case mileage

  var id: String { rawValue }

  var label: String {
    switch self {
    case .income: return "Earnings"
    case .expense: return "Expense"
    case .mileage: return "Mileage"
    }
  }

  var symbol: String {
    switch self {
    case .income: return "sterlingsign.circle.fill"
    case .expense: return "receipt.fill"
    case .mileage: return "map.fill"
    }
  }
}

struct RoutePoint: Identifiable, Codable, Equatable {
  var id = UUID()
  var latitude: Double
  var longitude: Double

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

struct NativeRecord: Identifiable, Codable, Equatable {
  var id = UUID()
  var kind: NativeLogKind
  var platform: String?
  var vehicle: NativeVehicle?
  var amount: Double?
  var miles: Double?
  var deduction: Double?
  var category: String?
  var merchant: String? = nil
  var date: Date
  var period: NativePayPeriod
  var receiptImageData: Data?
}

struct NativeTrip: Identifiable, Codable, Equatable {
  var id = UUID()
  var vehicle: NativeVehicle
  var miles: Double
  var deduction: Double
  var startedAt: Date
  var endedAt: Date
  var points: [RoutePoint]
}

enum NativePayPeriod: String, CaseIterable, Identifiable, Codable {
  case day
  case week

  var id: String { rawValue }
  var label: String { rawValue.capitalized }
}

enum NativeLogFrequency: String, CaseIterable, Identifiable, Codable {
  case weekly
  case monthly

  var id: String { rawValue }
  var label: String { rawValue.capitalized }
}

struct NativeSettings: Codable, Equatable {
  var name = ""
  var defaultVehicle: NativeVehicle = .car
  var region: NativeRegion = .ruk
  var platforms = ["Uber Eats", "Deliveroo", "Just Eat"]
  var loggingReminder = true
  var reminderDay = 1
  var logFrequency: NativeLogFrequency = .weekly
  var taxDeadlineReminders = true
  var tripNudges = false
}

struct NativeSnapshot: Codable {
  var settings: NativeSettings
  var records: [NativeRecord]
  var trips: [NativeTrip]
}

@MainActor
final class OkkleStore: ObservableObject {
  @Published var settings = NativeSettings() { didSet { save() } }
  @Published var records: [NativeRecord] = [] { didSet { save() } }
  @Published var trips: [NativeTrip] = [] { didSet { save() } }

  private let key = "uk.okkle.native.swiftui.snapshot.v1"
  private var isLoading = false

  init() {
    load()
  }

  func load() {
    isLoading = true
    defer { isLoading = false }
    guard let data = UserDefaults.standard.data(forKey: key) else { return }
    do {
      let snapshot = try JSONDecoder().decode(NativeSnapshot.self, from: data)
      settings = snapshot.settings
      records = snapshot.records
      trips = snapshot.trips
    } catch {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  func save() {
    guard !isLoading else { return }
    let snapshot = NativeSnapshot(settings: settings, records: records, trips: trips)
    if let data = try? JSONEncoder().encode(snapshot) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  func addRecord(_ record: NativeRecord) {
    records.insert(record, at: 0)
  }

  func addTrip(_ trip: NativeTrip) {
    trips.insert(trip, at: 0)
  }

  func deleteRecord(_ record: NativeRecord) {
    records.removeAll { $0.id == record.id }
  }

  func deleteTrip(_ trip: NativeTrip) {
    trips.removeAll { $0.id == trip.id }
  }

  func resetAllData() {
    records.removeAll()
    trips.removeAll()
  }

  var taxYear: DateInterval {
    taxYearInterval(containing: Date())
  }

  var yearRecords: [NativeRecord] {
    records.filter { taxYear.contains($0.date) }
  }

  var yearTrips: [NativeTrip] {
    trips.filter { taxYear.contains($0.startedAt) }
  }

  var yearMiles: Double {
    yearTrips.reduce(0) { $0 + $1.miles } + yearRecords.reduce(0) { $0 + ($1.kind == .mileage ? ($1.miles ?? 0) : 0) }
  }

  var yearMileageDeduction: Double {
    yearTrips.reduce(0) { $0 + $1.deduction } + yearRecords.reduce(0) { $0 + ($1.deduction ?? 0) }
  }

  var yearIncome: Double {
    yearRecords.reduce(0) { $0 + ($1.kind == .income ? ($1.amount ?? 0) : 0) }
  }

  var yearExpenses: Double {
    yearRecords.reduce(0) { $0 + ($1.kind == .expense ? ($1.amount ?? 0) : 0) } + yearMileageDeduction
  }

  var taxSaved: Double {
    yearMileageDeduction * 0.20
  }

  var taxPosition: NativeTaxPosition {
    estimateTax(turnover: yearIncome, expenses: yearExpenses, region: settings.region)
  }

  var history: [NativeHistoryItem] {
    let tripItems = trips.map(NativeHistoryItem.trip)
    let recordItems = records.map(NativeHistoryItem.record)
    return (tripItems + recordItems).sorted { $0.date > $1.date }
  }

  func calcDeduction(miles: Double, vehicle: NativeVehicle, totalBefore: Double = 0, date: Date = Date()) -> Double {
    let threshold = 10_000.0
    let band = vehicle.rateBand(on: date)
    if totalBefore >= threshold { return miles * band.after }
    let first = max(0, min(miles, threshold - totalBefore))
    let second = max(0, miles - first)
    return first * band.first + second * band.after
  }

  private func taxYearInterval(containing date: Date) -> DateInterval {
    let calendar = Calendar.current
    let year = calendar.component(.year, from: date)
    let currentStart = calendar.date(from: DateComponents(year: year, month: 4, day: 6)) ?? date
    let start: Date
    let end: Date
    if date < currentStart {
      start = calendar.date(from: DateComponents(year: year - 1, month: 4, day: 6)) ?? currentStart
      end = currentStart
    } else {
      start = currentStart
      end = calendar.date(from: DateComponents(year: year + 1, month: 4, day: 6)) ?? date
    }
    return DateInterval(start: start, end: end)
  }
}

enum NativeHistoryItem: Identifiable, Equatable {
  case trip(NativeTrip)
  case record(NativeRecord)

  var id: UUID {
    switch self {
    case .trip(let trip): return trip.id
    case .record(let record): return record.id
    }
  }

  var date: Date {
    switch self {
    case .trip(let trip): return trip.startedAt
    case .record(let record): return record.date
    }
  }
}

struct NativeTaxPosition {
  var turnover: Double
  var expenses: Double
  var profit: Double
  var incomeTax: Double
  var class4: Double
  var totalDue: Double
  var paymentOnAccount: Double
  var usesTradingAllowance: Bool
}

private func estimateTax(turnover: Double, expenses: Double, region: NativeRegion) -> NativeTaxPosition {
  let tradingAllowance = 1_000.0
  let deductible = min(turnover, max(expenses, tradingAllowance))
  let profit = max(0, turnover - deductible)
  let incomeTax = nativeIncomeTax(profit: profit, region: region)
  let class4 = nativeClass4(profit: profit)
  let total = incomeTax + class4
  return NativeTaxPosition(
    turnover: turnover,
    expenses: deductible,
    profit: profit,
    incomeTax: incomeTax,
    class4: class4,
    totalDue: total,
    paymentOnAccount: total > 1_000 ? total * 0.5 : 0,
    usesTradingAllowance: tradingAllowance > expenses
  )
}

private func nativeIncomeTax(profit: Double, region: NativeRegion) -> Double {
  let allowance = 12_570.0
  var taxable = max(0, profit - allowance)
  let bands: [(Double, Double)]
  switch region {
  case .ruk:
    bands = [(37_700, 0.20), (112_570, 0.40), (.infinity, 0.45)]
  case .scotland:
    bands = [(3_967, 0.19), (16_956, 0.20), (31_092, 0.21), (62_430, 0.42), (112_570, 0.45), (.infinity, 0.48)]
  }
  var tax = 0.0
  var previous = 0.0
  for band in bands {
    let slice = min(taxable, band.0) - previous
    if slice > 0 {
      tax += slice * band.1
      previous = min(taxable, band.0)
    }
    if taxable <= band.0 { break }
  }
  taxable = 0
  return max(0, tax + taxable)
}

private func nativeClass4(profit: Double) -> Double {
  guard profit > 12_570 else { return 0 }
  let main = min(profit, 50_270) - 12_570
  let upper = max(0, profit - 50_270)
  return main * 0.06 + upper * 0.02
}

struct OkkleNativeRootView: View {
  @StateObject private var store = OkkleStore()

  var body: some View {
    TabView {
      NativeHomeView()
        .tabItem { Label("Home", systemImage: "person.crop.circle") }
      NativeLogView()
        .tabItem { Label("Log", systemImage: "square.and.pencil") }
      NativeTripView()
        .tabItem { Label("Trip", systemImage: "location.north") }
      NativeInsightsView()
        .tabItem { Label("Insights", systemImage: "sparkles") }
      NativeRecordsView()
        .tabItem { Label("Records", systemImage: "archivebox") }
    }
    .environmentObject(store)
    .tint(OkkleColor.brand)
  }
}

struct NativeScreen<Content: View>: View {
  let title: String
  let subtitle: String?
  let content: Content
  @State private var showSettings = false

  init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
              Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(OkkleColor.ink)
              if let subtitle {
                Text(subtitle)
                  .font(.system(size: 16, weight: .medium))
                  .foregroundStyle(OkkleColor.muted)
              }
            }
            Spacer(minLength: 16)
            Button { showSettings = true } label: {
              Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(OkkleColor.ink)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
            }
            .accessibilityLabel("Settings")
          }
          .padding(.top, 14)

          content
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 120)
      }
      .background(NativeBackground())
      .scrollIndicators(.hidden)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") {
            hideKeyboard()
          }
          .fontWeight(.bold)
        }
      }
      .sheet(isPresented: $showSettings) {
        NativeSettingsView()
      }
    }
  }
}

struct NativeBackground: View {
  var body: some View {
    LinearGradient(
      colors: [Color.white, Color(red: 0.96, green: 0.99, blue: 0.98)],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
  }
}

struct NativeGlassCard<Content: View>: View {
  var cornerRadius: CGFloat = 26
  var content: Content

  init(cornerRadius: CGFloat = 26, @ViewBuilder content: () -> Content) {
    self.cornerRadius = cornerRadius
    self.content = content()
  }

  var body: some View {
    content
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(.white.opacity(0.68), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.07), radius: 22, y: 12)
  }
}

struct NativeAiCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    NativeGlassCard(cornerRadius: 30) {
      content
    }
    .shadow(color: Color(red: 0.32, green: 0.78, blue: 1.0).opacity(0.20), radius: 36, x: -18, y: 18)
    .shadow(color: Color(red: 0.58, green: 0.36, blue: 1.0).opacity(0.16), radius: 44, x: 20, y: 20)
    .shadow(color: Color(red: 1.0, green: 0.56, blue: 0.67).opacity(0.14), radius: 50, x: 0, y: -8)
  }
}

struct NativeMetricTile: View {
  let title: String
  let value: String
  let symbol: String
  var color: Color = OkkleColor.brand

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(color)
      Text(value)
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.7)
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

struct NativeFreeTextDropdown: View {
  let title: String
  let placeholder: String
  let options: [String]
  @Binding var text: String
  @FocusState private var focused: Bool
  @State private var expanded = false

  private var matches: [String] {
    var seen = Set<String>()
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return options.filter { option in
      let clean = option.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clean.isEmpty else { return false }
      let key = clean.lowercased()
      guard !seen.contains(key) else { return false }
      seen.insert(key)
      return query.isEmpty || clean.localizedCaseInsensitiveContains(query)
    }
    .prefix(7)
    .map { $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.ink)

      HStack(spacing: 8) {
        TextField(placeholder, text: $text)
          .textInputAutocapitalization(.words)
          .focused($focused)
          .onChange(of: text) { _ in expanded = true }
          .onTapGesture { expanded = true }

        Button {
          expanded.toggle()
          focused = expanded
        } label: {
          Image(systemName: expanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
      }
      .padding(.leading, 14)
      .padding(.trailing, 8)
      .padding(.vertical, 8)
      .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke((focused || expanded) ? OkkleColor.brand.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 1)
      )

      if (focused || expanded) && !matches.isEmpty {
        VStack(spacing: 0) {
          ForEach(matches, id: \.self) { option in
            Button {
              text = option
              expanded = false
              focused = false
              hideKeyboard()
            } label: {
              HStack {
                Text(option)
                  .font(.system(size: 15, weight: .semibold))
                  .foregroundStyle(OkkleColor.ink)
                Spacer()
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            if option != (matches.last ?? "") {
              Divider().padding(.leading, 14)
            }
          }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
      }
    }
  }
}

struct NativeSectionTitle: View {
  let title: String
  let symbol: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .foregroundStyle(OkkleColor.brand)
      Text(title)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
    }
  }
}

struct NativeHomeView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    NativeScreen(
      title: store.settings.name.isEmpty ? "Home" : "Hi, \(store.settings.name)",
      subtitle: "Your tax saved this year and progress."
    ) {
      NativeGlassCard(cornerRadius: 32) {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Label("Tax saved this year", systemImage: "chart.line.uptrend.xyaxis")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(OkkleColor.brandDark)
            Spacer()
            Text(taxYearLabel(for: store.taxYear))
              .font(.caption.weight(.semibold))
              .foregroundStyle(OkkleColor.muted)
          }
          Text(gbp(store.taxSaved, whole: true))
            .font(.system(size: 58, weight: .heavy, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
            .minimumScaleFactor(0.55)
          Text("From \(miles(store.yearMiles)) and \(gbp(store.yearMileageDeduction, whole: true)) of mileage deductions.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
          ProgressView(value: min(1, store.yearMiles / 10_000))
            .tint(OkkleColor.brand)
        }
      }

      HStack(spacing: 12) {
        NativeMetricTile(title: "Mileage", value: miles(store.yearMiles), symbol: "road.lanes")
        NativeMetricTile(title: "Earnings", value: gbp(store.yearIncome, whole: true), symbol: "sterlingsign.circle.fill", color: .green)
      }

      NativeSectionTitle(title: "Progress", symbol: "sparkles")
      NativeGlassCard {
        VStack(alignment: .leading, spacing: 16) {
          progressRow("First 10k mileage band", value: min(1, store.yearMiles / 10_000), trailing: "\(Int(min(10_000, store.yearMiles)).formatted()) / 10,000 mi")
          progressRow("Records logged", value: min(1, Double(store.records.count) / 24), trailing: "\(store.records.count) entries")
          progressRow("Trips tracked", value: min(1, Double(store.trips.count) / 20), trailing: "\(store.trips.count) trips")
        }
      }

      NativeSectionTitle(title: "Recent activity", symbol: "clock")
      if store.history.isEmpty {
        NativeEmptyState(symbol: "tray", title: "No records yet", message: "Track a trip or log earnings and expenses to see your history here.")
      } else {
        NativeGlassCard {
          VStack(spacing: 0) {
            ForEach(store.history.prefix(4)) { item in
              NativeHistoryRow(item: item)
              if item.id != store.history.prefix(4).last?.id {
                Divider().padding(.leading, 52)
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func progressRow(_ title: String, value: Double, trailing: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
        Spacer()
        Text(trailing)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }
      ProgressView(value: value)
        .tint(OkkleColor.brand)
    }
  }

  private func taxYearLabel(for interval: DateInterval) -> String {
    let start = Calendar.current.component(.year, from: interval.start)
    let end = Calendar.current.component(.year, from: interval.end)
    return "\(start)/\(String(end).suffix(2))"
  }
}

private let nativeExpenseCategories = [
  "Fuel",
  "Charging",
  "Parking",
  "Phone / data",
  "Insurance",
  "Maintenance / repairs",
  "Tyres",
  "Congestion charge",
  "ULEZ charge",
  "Insulated bag",
  "Waterproof gear",
  "Helmet / safety",
  "Phone mount",
  "App subscription",
]

struct NativeLogView: View {
  @EnvironmentObject private var store: OkkleStore
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

            receiptBetaPanel
          }

          Picker("Period", selection: $period) {
            ForEach(NativePayPeriod.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)

          DatePicker("Date", selection: $date, displayedComponents: .date)
            .datePickerStyle(.compact)

          Button(action: saveRecord) {
            Label("Continue", systemImage: "arrow.right.circle.fill")
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
    .alert("Saved to records", isPresented: Binding(get: { savedRecord != nil }, set: { if !$0 { savedRecord = nil } })) {
      Button("Done") {
        resetEntry()
        savedRecord = nil
      }
    } message: {
      Text(savedMessage)
    }
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
    VStack(alignment: .leading, spacing: 12) {
      Label("Receipt scan beta", systemImage: "wand.and.stars")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(OkkleColor.brandDark)
      Text("Attach a receipt photo now. On-device reading can be layered into this native flow next.")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(OkkleColor.muted)

      HStack(spacing: 10) {
        PhotosPicker(selection: $receiptItem, matching: .images) {
          Label("Photos (Beta)", systemImage: "photo")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
          showCamera = true
        } label: {
          Label("Camera (Beta)", systemImage: "camera")
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
    .padding(14)
    .background(OkkleColor.mint.opacity(0.70), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
    }
  }

  private func saveRecord() {
    let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
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
  }
}

private func uniqueStrings(_ values: [String]) -> [String] {
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

final class NativeTripSession: NSObject, ObservableObject, CLLocationManagerDelegate {
  enum Phase {
    case setup
    case live
    case paused
    case summary
  }

  @Published var phase: Phase = .setup
  @Published var vehicle: NativeVehicle = .car
  @Published var miles: Double = 0
  @Published var elapsed: TimeInterval = 0
  @Published var points: [RoutePoint] = []
  @Published var permissionMessage: String?

  private let manager = CLLocationManager()
  private var lastLocation: CLLocation?
  private var startedAt: Date?
  private var timer: Timer?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 12
    manager.activityType = .automotiveNavigation
  }

  func start(vehicle: NativeVehicle) {
    self.vehicle = vehicle
    permissionMessage = nil
    let status = manager.authorizationStatus
    if status == .notDetermined {
      manager.requestWhenInUseAuthorization()
    }
    guard status == .authorizedAlways || status == .authorizedWhenInUse || status == .notDetermined else {
      permissionMessage = "Location permission is needed to track trip distance."
      return
    }
    miles = 0
    elapsed = 0
    points = []
    lastLocation = nil
    startedAt = Date()
    phase = .live
    manager.startUpdatingLocation()
    startTimer()
  }

  func pause() {
    guard phase == .live else { return }
    phase = .paused
    manager.stopUpdatingLocation()
    stopTimer()
  }

  func resume() {
    guard phase == .paused else { return }
    phase = .live
    manager.startUpdatingLocation()
    startTimer()
  }

  @MainActor
  func end(store: OkkleStore) -> NativeTrip? {
    guard let startedAt else { return nil }
    manager.stopUpdatingLocation()
    stopTimer()
    phase = .summary
    let trip = NativeTrip(
      vehicle: vehicle,
      miles: miles,
      deduction: store.calcDeduction(miles: miles, vehicle: vehicle, date: startedAt),
      startedAt: startedAt,
      endedAt: Date(),
      points: points
    )
    return trip
  }

  func discard() {
    manager.stopUpdatingLocation()
    stopTimer()
    miles = 0
    elapsed = 0
    points = []
    lastLocation = nil
    startedAt = nil
    phase = .setup
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    if status == .authorizedAlways || status == .authorizedWhenInUse {
      permissionMessage = nil
      if phase == .live {
        manager.startUpdatingLocation()
      }
    } else if status == .denied || status == .restricted {
      permissionMessage = "Location permission is needed to track trip distance."
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard phase == .live else { return }
    for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 60 {
      if let lastLocation {
        let delta = location.distance(from: lastLocation) / 1_609.344
        if delta > 0.003 && delta < 1 {
          miles += delta
        }
      }
      lastLocation = location
      points.append(RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    permissionMessage = error.localizedDescription
  }

  private func startTimer() {
    stopTimer()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let self, let startedAt = self.startedAt else { return }
      self.elapsed = Date().timeIntervalSince(startedAt)
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }
}

struct NativeTripView: View {
  @EnvironmentObject private var store: OkkleStore
  @StateObject private var session = NativeTripSession()
  @State private var selectedVehicle: NativeVehicle = .car
  @State private var completedTrip: NativeTrip?

  var body: some View {
    NativeScreen(title: "Trip", subtitle: "Track GPS miles for HMRC mileage relief.") {
      NativeGlassCard(cornerRadius: 34) {
        VStack(spacing: 22) {
          Picker("Vehicle", selection: $selectedVehicle) {
            ForEach(NativeVehicle.allCases) { vehicle in
              Label(vehicle.label, systemImage: vehicle.symbol).tag(vehicle)
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .leading)
          .disabled(session.phase == .live || session.phase == .paused)

          ZStack {
            Circle()
              .stroke(OkkleColor.mint, lineWidth: 18)
              .frame(width: 270, height: 270)
            Circle()
              .fill(
                LinearGradient(colors: [OkkleColor.brand, OkkleColor.brandDark], startPoint: .topLeading, endPoint: .bottomTrailing)
              )
              .frame(width: 222, height: 222)
              .shadow(color: OkkleColor.brand.opacity(0.32), radius: 28, y: 20)

            VStack(spacing: 8) {
              if session.phase == .setup {
                Image(systemName: "location.north.fill")
                  .font(.system(size: 42, weight: .bold))
                Text("Start")
                  .font(.system(size: 38, weight: .heavy, design: .rounded))
              } else {
                Text(miles(session.miles))
                  .font(.system(size: 44, weight: .heavy, design: .rounded))
                  .minimumScaleFactor(0.6)
                Text(session.phase == .paused ? "Paused" : "Recording")
                  .font(.system(size: 16, weight: .bold))
              }
            }
            .foregroundStyle(.white)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Circle())
          .onTapGesture {
            if session.phase == .setup {
              session.start(vehicle: selectedVehicle)
            }
          }

          HStack(spacing: 12) {
            NativeMetricTile(title: "Tax deduction", value: gbp(store.calcDeduction(miles: session.miles, vehicle: selectedVehicle), whole: true), symbol: "sterlingsign.arrow.circlepath")
            NativeMetricTile(title: "Elapsed", value: elapsedLabel(session.elapsed), symbol: "timer", color: OkkleColor.blue)
          }

          if !session.points.isEmpty {
            NativeTripMap(points: session.points)
              .frame(height: 190)
              .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
          }

          if let message = session.permissionMessage {
            Label(message, systemImage: "location.slash")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(OkkleColor.red)
              .padding(12)
              .background(OkkleColor.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
          }

          tripControls
        }
      }
    }
    .alert("Save this trip?", isPresented: Binding(get: { completedTrip != nil }, set: { if !$0 { completedTrip = nil } })) {
      Button("Discard", role: .destructive) {
        completedTrip = nil
        session.discard()
      }
      Button("Save") {
        if let completedTrip {
          store.addTrip(completedTrip)
        }
        completedTrip = nil
        session.discard()
      }
    } message: {
      if let completedTrip {
        Text("\(miles(completedTrip.miles)) with \(gbp(completedTrip.deduction, whole: true)) deduction.")
      }
    }
    .onAppear {
      selectedVehicle = store.settings.defaultVehicle
    }
  }

  private var tripControls: some View {
    HStack(spacing: 12) {
      switch session.phase {
      case .setup:
        Button {
          session.start(vehicle: selectedVehicle)
        } label: {
          Label("Start trip", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(OkkleColor.brand)
      case .live:
        Button {
          session.pause()
        } label: {
          Label("Pause", systemImage: "pause.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
          completedTrip = session.end(store: store)
        } label: {
          Label("End", systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(OkkleColor.red)
      case .paused:
        Button {
          session.resume()
        } label: {
          Label("Resume", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(OkkleColor.brand)

        Button(role: .destructive) {
          completedTrip = session.end(store: store)
        } label: {
          Label("End", systemImage: "stop.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      case .summary:
        EmptyView()
      }
    }
    .font(.system(size: 16, weight: .bold))
  }

  private func elapsedLabel(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }
}

struct NativeTripMap: View {
  let points: [RoutePoint]
  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
  )

  var body: some View {
    Map(coordinateRegion: $region, annotationItems: Array(points.suffix(1))) { point in
      MapMarker(coordinate: point.coordinate, tint: OkkleColor.brand)
    }
    .onAppear(perform: updateRegion)
    .onChange(of: points) { _ in updateRegion() }
  }

  private func updateRegion() {
    guard let last = points.last else { return }
    region = MKCoordinateRegion(center: last.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
  }
}

struct NativeInsightsView: View {
  @EnvironmentObject private var store: OkkleStore
  private let weekdays = Calendar.current.shortWeekdaySymbols

  var body: some View {
    NativeScreen(title: "Insights", subtitle: "AI guidance, smart nudges and patterns from your work.") {
      NativeAiCard {
        VStack(alignment: .leading, spacing: 16) {
          cardHeader("Trip nudges", symbol: "location.north.circle.fill", color: OkkleColor.blue)
          Text("Never forget to track a trip")
            .font(.system(size: 26, weight: .bold, design: .rounded))
          Text("Okkle watches both ends of your trip. When it senses you have started driving it nudges you to start tracking, then reminds you to end and save your miles once you have stopped.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
          Toggle("Trip nudges", isOn: Binding(
            get: { store.settings.tripNudges },
            set: { store.settings.tripNudges = $0 }
          ))
          .font(.system(size: 17, weight: .bold))
          .tint(OkkleColor.brand)
          Label("Detection is a prompt, not auto-logging. Nothing is recorded until you confirm.", systemImage: "exclamationmark.circle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(OkkleColor.amber)
            .padding(14)
            .background(Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        }
      }

      NativeAiCard {
        VStack(alignment: .leading, spacing: 16) {
          cardHeader("Reminders", symbol: "bell.circle.fill", color: .purple)
          Text("Keep your records fresh")
            .font(.system(size: 26, weight: .bold, design: .rounded))

          Toggle("Logging reminder", isOn: Binding(
            get: { store.settings.loggingReminder },
            set: { store.settings.loggingReminder = $0 }
          ))
          .font(.system(size: 17, weight: .bold))
          .tint(OkkleColor.brand)

          if store.settings.loggingReminder {
            Picker("Frequency", selection: Binding(
              get: { store.settings.logFrequency },
              set: { store.settings.logFrequency = $0 }
            )) {
              ForEach(NativeLogFrequency.allCases) { frequency in
                Text(frequency.label).tag(frequency)
              }
            }
            .pickerStyle(.segmented)

            Picker("Reminder day", selection: Binding(
              get: { store.settings.reminderDay },
              set: { store.settings.reminderDay = $0 }
            )) {
              ForEach(0..<weekdays.count, id: \.self) { index in
                Text(weekdays[index]).tag(index)
              }
            }
            .pickerStyle(.segmented)
          }

          Divider()

          Toggle("Tax deadline reminders", isOn: Binding(
            get: { store.settings.taxDeadlineReminders },
            set: { store.settings.taxDeadlineReminders = $0 }
          ))
          .font(.system(size: 17, weight: .bold))
          .tint(OkkleColor.brand)

          NativeTaxDatesPreview()
        }
      }

      if store.history.isEmpty {
        NativeEmptyState(symbol: "sparkles", title: "Insights will grow with your data", message: "Track trips and log pay to unlock best zones, hours, platform mix and tax-aware suggestions.")
      } else {
        NativeGlassCard {
          VStack(alignment: .leading, spacing: 12) {
            NativeSectionTitle(title: "First native insight", symbol: "lightbulb.fill")
            Text("You have logged \(store.records.count) records and \(store.trips.count) trips. Your current mileage deduction is \(gbp(store.yearMileageDeduction, whole: true)).")
              .font(.system(size: 16, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
          }
        }
      }
    }
  }

  private func cardHeader(_ title: String, symbol: String, color: Color) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 42, height: 42)
        .background(color.opacity(0.14), in: Circle())
      Text(title.uppercased())
        .font(.system(size: 15, weight: .heavy))
        .foregroundStyle(.purple)
    }
  }
}

struct NativeTaxDatesPreview: View {
  private let rows = [
    ("31 Jan", "Self Assessment return and balancing payment"),
    ("31 Jul", "Second payment on account"),
    ("5 Apr", "Tax year ends")
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Key tax dates")
        .font(.system(size: 16, weight: .bold))
      ForEach(rows, id: \.0) { row in
        HStack {
          Text(row.0)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(OkkleColor.brandDark)
            .frame(width: 54, alignment: .leading)
          Text(row.1)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
          Spacer()
        }
      }
    }
  }
}

struct NativeRecordsView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var mode: RecordsMode = .history
  @State private var filter: RecordsFilter = .all

  enum RecordsMode: String, CaseIterable, Identifiable {
    case history
    case tax

    var id: String { rawValue }
  }

  enum RecordsFilter: String, CaseIterable, Identifiable {
    case all
    case trips
    case income
    case expense

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
  }

  var body: some View {
    NativeScreen(title: "Records", subtitle: "Your logs, tax estimate and export-ready history.") {
      Picker("Mode", selection: $mode) {
        Text("History").tag(RecordsMode.history)
        Text("Tax").tag(RecordsMode.tax)
      }
      .pickerStyle(.segmented)

      if mode == .history {
        Picker("Filter", selection: $filter) {
          ForEach(RecordsFilter.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        if filteredHistory.isEmpty {
          NativeEmptyState(symbol: "archivebox", title: "Nothing here yet", message: "Trips, earnings and expenses appear here after you save them.")
        } else {
          NativeGlassCard {
            VStack(spacing: 0) {
              ForEach(filteredHistory) { item in
                NativeHistoryRow(item: item)
                  .contextMenu {
                    Button(role: .destructive) {
                      delete(item)
                    } label: {
                      Label("Delete", systemImage: "trash")
                    }
                  }
                if item.id != filteredHistory.last?.id {
                  Divider().padding(.leading, 52)
                }
              }
            }
          }
        }
      } else {
        NativeTaxSummaryView()
      }
    }
  }

  private var filteredHistory: [NativeHistoryItem] {
    store.history.filter { item in
      switch filter {
      case .all:
        return true
      case .trips:
        if case .trip = item { return true }
        if case .record(let record) = item { return record.kind == .mileage }
        return false
      case .income:
        if case .record(let record) = item { return record.kind == .income }
        return false
      case .expense:
        if case .record(let record) = item { return record.kind == .expense }
        return false
      }
    }
  }

  private func delete(_ item: NativeHistoryItem) {
    switch item {
    case .trip(let trip):
      store.deleteTrip(trip)
    case .record(let record):
      store.deleteRecord(record)
    }
  }
}

struct NativeHistoryRow: View {
  let item: NativeHistoryItem

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 40, height: 40)
        .background(tint.opacity(0.13), in: Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
          .lineLimit(1)
        Text(subtitle)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .lineLimit(1)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text(value)
          .font(.system(size: 16, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        if let detail {
          Text(detail)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(OkkleColor.muted)
        }
      }
    }
    .padding(.vertical, 12)
  }

  private var symbol: String {
    switch item {
    case .trip: return "location.north.fill"
    case .record(let record): return record.kind.symbol
    }
  }

  private var tint: Color {
    switch item {
    case .trip: return OkkleColor.blue
    case .record(let record):
      switch record.kind {
      case .income: return .green
      case .expense: return OkkleColor.amber
      case .mileage: return OkkleColor.brand
      }
    }
  }

  private var title: String {
    switch item {
    case .trip(let trip): return "Trip - \(trip.vehicle.label)"
    case .record(let record):
      switch record.kind {
      case .income: return record.platform ?? "Earnings"
      case .expense: return record.category ?? "Expense"
      case .mileage: return "Mileage - \(record.vehicle?.label ?? "Vehicle")"
      }
    }
  }

  private var subtitle: String {
    switch item {
    case .trip(let trip): return "GPS - \(shortDate(trip.startedAt))"
    case .record(let record):
      if record.kind == .expense, let merchant = record.merchant, !merchant.isEmpty {
        return "\(merchant) - \(shortDate(record.date))"
      }
      return "\(record.kind.label) - \(shortDate(record.date))"
    }
  }

  private var value: String {
    switch item {
    case .trip(let trip): return miles(trip.miles)
    case .record(let record):
      if record.kind == .mileage { return miles(record.miles ?? 0) }
      return gbp(record.amount ?? 0)
    }
  }

  private var detail: String? {
    switch item {
    case .trip(let trip): return gbp(trip.deduction, whole: true)
    case .record(let record):
      if let deduction = record.deduction { return gbp(deduction, whole: true) }
      return record.period.label
    }
  }
}

struct NativeTaxSummaryView: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    let tax = store.taxPosition
    VStack(spacing: 14) {
      NativeGlassCard(cornerRadius: 32) {
        VStack(alignment: .leading, spacing: 14) {
          Label("Estimated tax due", systemImage: "shield.lefthalf.filled")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(OkkleColor.brandDark)
          Text(gbp(tax.totalDue, whole: true))
            .font(.system(size: 52, weight: .heavy, design: .rounded))
          Text("Estimate only, not tax advice. Built from your logged earnings, expenses and mileage.")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
        }
      }

      HStack(spacing: 12) {
        NativeMetricTile(title: "Turnover", value: gbp(tax.turnover, whole: true), symbol: "sterlingsign.circle.fill", color: .green)
        NativeMetricTile(title: "Expenses", value: gbp(tax.expenses, whole: true), symbol: "minus.circle.fill", color: OkkleColor.amber)
      }

      NativeGlassCard {
        VStack(spacing: 12) {
          taxRow("Profit", gbp(tax.profit, whole: true))
          taxRow("Income tax", gbp(tax.incomeTax, whole: true))
          taxRow("Class 4 NIC", gbp(tax.class4, whole: true))
          taxRow("Payment on account", gbp(tax.paymentOnAccount, whole: true))
          taxRow("Trading allowance", tax.usesTradingAllowance ? "Used" : "Not used")
        }
      }
    }
  }

  private func taxRow(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Spacer()
      Text(value)
        .font(.system(size: 16, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
    }
  }
}

struct NativeSettingsView: View {
  @EnvironmentObject private var store: OkkleStore
  @Environment(\.dismiss) private var dismiss
  @State private var newPlatform = ""

  var body: some View {
    NavigationStack {
      Form {
        Section("Profile") {
          TextField("Name", text: Binding(
            get: { store.settings.name },
            set: { store.settings.name = $0 }
          ))

          Picker("Region", selection: Binding(
            get: { store.settings.region },
            set: { store.settings.region = $0 }
          )) {
            ForEach(NativeRegion.allCases) { Text($0.label).tag($0) }
          }

          Picker("Default vehicle", selection: Binding(
            get: { store.settings.defaultVehicle },
            set: { store.settings.defaultVehicle = $0 }
          )) {
            ForEach(NativeVehicle.allCases) { vehicle in
              Label(vehicle.label, systemImage: vehicle.symbol).tag(vehicle)
            }
          }
        }

        Section("Platforms") {
          ForEach(store.settings.platforms, id: \.self) { platform in
            Text(platform)
          }
          .onDelete { offsets in
            store.settings.platforms.remove(atOffsets: offsets)
            if store.settings.platforms.isEmpty {
              store.settings.platforms = ["Uber Eats"]
            }
          }

          HStack {
            TextField("Add platform", text: $newPlatform)
            Button("Add") {
              let clean = newPlatform.trimmingCharacters(in: .whitespacesAndNewlines)
              guard !clean.isEmpty else { return }
              if !store.settings.platforms.contains(clean) {
                store.settings.platforms.append(clean)
              }
              newPlatform = ""
            }
          }
        }

        Section("Data") {
          Button(role: .destructive) {
            store.resetAllData()
          } label: {
            Label("Clear records and trips", systemImage: "trash")
          }
        }

        Section("Build") {
          HStack {
            Text("Version")
            Spacer()
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4")
              .foregroundStyle(.secondary)
          }
          Text("Native SwiftUI iPhone rebuild for the 0.4 branch.")
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
    }
  }
}

struct NativeEmptyState: View {
  let symbol: String
  let title: String
  let message: String

  var body: some View {
    NativeGlassCard {
      VStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(OkkleColor.brand)
          .frame(width: 68, height: 68)
          .background(OkkleColor.mint, in: Circle())
        Text(title)
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        Text(message)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
    }
  }
}
