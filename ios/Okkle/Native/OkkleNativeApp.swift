import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SwiftUI
import UIKit
import Vision

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

private func nativeTaxYearLabel(for interval: DateInterval) -> String {
  let start = Calendar.current.component(.year, from: interval.start)
  let end = Calendar.current.component(.year, from: interval.end)
  return "\(start)/\(String(end).suffix(2))"
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

struct NativeBackupPayload: Codable {
  var app: String
  var version: Int
  var exportedAt: Date
  var snapshot: NativeSnapshot
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

  var backupPayload: NativeBackupPayload {
    NativeBackupPayload(
      app: "okkle",
      version: 1,
      exportedAt: Date(),
      snapshot: NativeSnapshot(settings: settings, records: records, trips: trips)
    )
  }

  func backupData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(backupPayload)
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

enum NativeTab {
  case home
  case log
  case trip
  case insights
  case records
}

struct OkkleNativeRootView: View {
  @StateObject private var store = OkkleStore()
  @State private var selectedTab: NativeTab = .home

  var body: some View {
    TabView(selection: $selectedTab) {
      NativeHomeView()
        .tabItem { Label("Home", systemImage: "person.crop.circle") }
        .tag(NativeTab.home)
      NativeLogView(selectedTab: $selectedTab)
        .tabItem { Label("Log", systemImage: "square.and.pencil") }
        .tag(NativeTab.log)
      NativeTripView()
        .tabItem { Label("Trip", systemImage: "location.north") }
        .tag(NativeTab.trip)
      NativeInsightsView()
        .tabItem { Label("Insights", systemImage: "sparkles") }
        .tag(NativeTab.insights)
      NativeRecordsView()
        .tabItem { Label("Records", systemImage: "archivebox") }
        .tag(NativeTab.records)
    }
    .environmentObject(store)
    .tint(OkkleColor.brand)
  }
}

enum NativeScreenStyle {
  case standard
  case dark

  var titleColor: Color {
    switch self {
    case .standard: return OkkleColor.ink
    case .dark: return .white
    }
  }

  var subtitleColor: Color {
    switch self {
    case .standard: return OkkleColor.muted
    case .dark: return Color.white.opacity(0.62)
    }
  }

  var settingsColor: Color {
    switch self {
    case .standard: return OkkleColor.ink
    case .dark: return .white
    }
  }

  var navigationColorScheme: ColorScheme {
    switch self {
    case .standard: return .light
    case .dark: return .dark
    }
  }
}

struct NativeScreen<Content: View>: View {
  let title: String
  let subtitle: String?
  let style: NativeScreenStyle
  let content: Content
  @State private var showSettings = false

  init(title: String, subtitle: String? = nil, style: NativeScreenStyle = .standard, @ViewBuilder content: () -> Content) {
    self.title = title
    self.subtitle = subtitle
    self.style = style
    self.content = content()
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let subtitle {
            Text(subtitle)
              .font(.system(size: 17, weight: .medium))
              .foregroundStyle(style.subtitleColor)
              .padding(.top, 2)
          }

          content
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 120)
      }
      .scrollIndicators(.hidden)
      .background {
        switch style {
        case .standard:
          NativeBackground()
        case .dark:
          Color.black.ignoresSafeArea()
        }
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.large)
      .toolbarColorScheme(style.navigationColorScheme, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button { showSettings = true } label: {
            Image(systemName: "gearshape")
              .font(.system(size: 17, weight: .semibold))
          }
          .accessibilityLabel("Settings")
        }
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
    receiptScanMessage = "Add a receipt and Okkle will try to fill the expense details."
    receiptScanning = false
  }
}

private struct NativeReceiptScanResult {
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

private func nativeParseReceipt(lines: [String]) -> NativeReceiptScanResult {
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

private func nativeReceiptAmount(from text: String) -> Double? {
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

private func nativeReceiptCategory(from text: String) -> String? {
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

private func nativeReceiptMerchant(from lines: [String]) -> String? {
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
  private var waitingForAuthorization = false

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    manager.distanceFilter = 5
    manager.activityType = .automotiveNavigation
    manager.pausesLocationUpdatesAutomatically = false
    let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    if backgroundModes.contains("location") {
      manager.allowsBackgroundLocationUpdates = true
      manager.showsBackgroundLocationIndicator = true
    }
  }

  func start(vehicle: NativeVehicle) {
    self.vehicle = vehicle
    permissionMessage = nil
    let status = manager.authorizationStatus
    if status == .notDetermined {
      waitingForAuthorization = true
      manager.requestWhenInUseAuthorization()
      return
    }
    guard status == .authorizedAlways || status == .authorizedWhenInUse else {
      permissionMessage = "Location permission is needed to track trip distance."
      return
    }
    beginTracking()
  }

  private func beginTracking() {
    miles = 0
    elapsed = 0
    points = []
    lastLocation = nil
    startedAt = Date()
    phase = .live
    manager.startUpdatingLocation()
    startTimer()
    waitingForAuthorization = false
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
    waitingForAuthorization = false
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
      if waitingForAuthorization {
        beginTracking()
      } else if phase == .live {
        manager.startUpdatingLocation()
      }
    } else if status == .denied || status == .restricted {
      waitingForAuthorization = false
      permissionMessage = "Location permission is needed to track trip distance."
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard phase == .live else { return }
    for location in locations where shouldUse(location) {
      if let lastLocation {
        let delta = location.distance(from: lastLocation) / 1_609.344
        if delta > 0.002 && delta < 1 {
          miles += delta
        }
      }
      lastLocation = location
      points.append(RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    }
  }

  private func shouldUse(_ location: CLLocation) -> Bool {
    guard location.horizontalAccuracy >= 0 else { return false }
    guard abs(location.timestamp.timeIntervalSinceNow) < 30 else { return false }
    // iOS can provide approximate or still-settling GPS fixes above 60m accuracy.
    // Keep those points so the trip visibly starts instead of staying at 0.
    return location.horizontalAccuracy <= 250
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
    NativeScreen(title: "Trip", subtitle: "Track GPS miles for HMRC mileage relief.", style: .dark) {
      VStack(spacing: 22) {
        Picker("Vehicle", selection: $selectedVehicle) {
          ForEach(NativeVehicle.allCases) { vehicle in
            Label(vehicle.label, systemImage: vehicle.symbol).tag(vehicle)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(session.phase == .live || session.phase == .paused)
        .tint(.white)

        ZStack {
          Circle()
            .stroke(OkkleColor.mint.opacity(0.18), lineWidth: 18)
            .frame(width: 270, height: 270)
          Circle()
            .fill(
              LinearGradient(colors: [OkkleColor.brand, OkkleColor.brandDark], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 222, height: 222)
            .shadow(color: OkkleColor.brand.opacity(0.45), radius: 34, y: 22)

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
            .background(OkkleColor.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
        }

        if session.phase != .setup {
          tripControls
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 34, style: .continuous)
          .stroke(Color.white.opacity(0.10), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.24), radius: 28, y: 16)
      .colorScheme(.dark)
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

private enum NativeTimeFilter: String, CaseIterable, Identifiable {
  case all
  case morning
  case lunch
  case afternoon
  case dinner
  case late

  var id: String { rawValue }

  var label: String {
    switch self {
    case .all: return "All day"
    case .morning: return "Morning"
    case .lunch: return "Lunch"
    case .afternoon: return "Afternoon"
    case .dinner: return "Dinner"
    case .late: return "Late"
    }
  }

  func includes(_ date: Date) -> Bool {
    if self == .all { return true }
    let hour = Calendar.current.component(.hour, from: date)
    switch self {
    case .all:
      return true
    case .morning:
      return hour >= 6 && hour < 11
    case .lunch:
      return hour >= 11 && hour < 14
    case .afternoon:
      return hour >= 14 && hour < 17
    case .dinner:
      return hour >= 17 && hour < 21
    case .late:
      return hour >= 21 || hour < 6
    }
  }
}

private struct NativeHeatPoint: Identifiable, Equatable {
  let id: String
  let latitude: Double
  let longitude: Double
  let weight: Double

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

private struct NativeHeatBubble: Identifiable {
  let id: String
  let latitude: Double
  let longitude: Double
  let weight: Double
  let normalized: Double

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  var diameter: CGFloat {
    CGFloat(34 + (normalized * 54))
  }
}

private func nativeHeatPoints(from trips: [NativeTrip], filter: NativeTimeFilter) -> [NativeHeatPoint] {
  var points: [NativeHeatPoint] = []
  for trip in trips where filter.includes(trip.startedAt) {
    guard !trip.points.isEmpty else { continue }
    let stride = max(1, trip.points.count / 160)
    let sampled = trip.points.enumerated().filter { $0.offset % stride == 0 }
    let weight = max(0.35, trip.miles / Double(max(sampled.count, 1)))
    for item in sampled {
      points.append(NativeHeatPoint(
        id: "\(trip.id.uuidString)-\(item.offset)",
        latitude: item.element.latitude,
        longitude: item.element.longitude,
        weight: weight
      ))
    }
  }
  return points
}

private func nativeDistinctCoordinateCount(_ points: [NativeHeatPoint]) -> Int {
  Set(points.map { "\(String(format: "%.3f", $0.latitude)),\(String(format: "%.3f", $0.longitude))" }).count
}

private func nativeHeatRegion(for points: [NativeHeatPoint]) -> MKCoordinateRegion {
  guard !points.isEmpty else {
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
      span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
  }

  var minLat = Double.infinity
  var maxLat = -Double.infinity
  var minLng = Double.infinity
  var maxLng = -Double.infinity

  for point in points {
    minLat = min(minLat, point.latitude)
    maxLat = max(maxLat, point.latitude)
    minLng = min(minLng, point.longitude)
    maxLng = max(maxLng, point.longitude)
  }

  return MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
    span: MKCoordinateSpan(
      latitudeDelta: max((maxLat - minLat) * 1.7, 0.012),
      longitudeDelta: max((maxLng - minLng) * 1.7, 0.012)
    )
  )
}

private func nativeHeatBubbles(from points: [NativeHeatPoint]) -> [NativeHeatBubble] {
  guard !points.isEmpty else { return [] }

  var minLat = Double.infinity
  var maxLat = -Double.infinity
  var minLng = Double.infinity
  var maxLng = -Double.infinity

  for point in points {
    minLat = min(minLat, point.latitude)
    maxLat = max(maxLat, point.latitude)
    minLng = min(minLng, point.longitude)
    maxLng = max(maxLng, point.longitude)
  }

  let cols = 18
  let rows = 18
  let latSpan = max(maxLat - minLat, 0.0001)
  let lngSpan = max(maxLng - minLng, 0.0001)

  struct Accumulator {
    var latitude = 0.0
    var longitude = 0.0
    var weight = 0.0
  }

  var buckets: [String: Accumulator] = [:]
  for point in points {
    let col = min(cols - 1, max(0, Int(((point.longitude - minLng) / lngSpan) * Double(cols))))
    let row = min(rows - 1, max(0, Int(((maxLat - point.latitude) / latSpan) * Double(rows))))
    let key = "\(row)-\(col)"
    var bucket = buckets[key] ?? Accumulator()
    bucket.latitude += point.latitude * point.weight
    bucket.longitude += point.longitude * point.weight
    bucket.weight += point.weight
    buckets[key] = bucket
  }

  let maxWeight = max(buckets.values.map(\.weight).max() ?? 1, 1)
  return buckets.map { key, bucket in
    let safeWeight = max(bucket.weight, 0.0001)
    return NativeHeatBubble(
      id: key,
      latitude: bucket.latitude / safeWeight,
      longitude: bucket.longitude / safeWeight,
      weight: bucket.weight,
      normalized: min(1, bucket.weight / maxWeight)
    )
  }
  .sorted { $0.weight > $1.weight }
  .prefix(90)
  .map { $0 }
}

private func nativeHeatColor(_ value: Double) -> Color {
  switch value {
  case ..<0.2:
    return Color(red: 0.61, green: 0.89, blue: 0.82)
  case ..<0.4:
    return Color(red: 0.37, green: 0.82, blue: 0.73)
  case ..<0.6:
    return Color(red: 0.91, green: 0.78, blue: 0.42)
  case ..<0.8:
    return Color(red: 0.88, green: 0.59, blue: 0.12)
  default:
    return Color(red: 0.89, green: 0.38, blue: 0.29)
  }
}

private struct NativeHeatMapCard: View {
  let points: [NativeHeatPoint]
  let showsFilters: Bool
  @Binding var filter: NativeTimeFilter

  var body: some View {
    NativeAiCard {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 10) {
          Image(systemName: "map.circle.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(OkkleColor.brand)
            .frame(width: 42, height: 42)
            .background(OkkleColor.brand.opacity(0.14), in: Circle())
          Text("HOTSPOT MAP")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.purple)
        }
        Text("See where your work clusters")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Okkle maps your saved GPS trips so you can spot the areas you keep returning to.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
        if showsFilters {
          NativeHeatFilterBar(selection: $filter)
        }
        NativeHeatMapView(points: points)
        NativeHeatLegend()
        Text("Built on-device from your trip breadcrumbs.")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct NativeHeatFilterBar: View {
  @Binding var selection: NativeTimeFilter

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(NativeTimeFilter.allCases) { filter in
          Button {
            selection = filter
          } label: {
            Text(filter.label)
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(selection == filter ? Color.white : OkkleColor.muted)
              .padding(.horizontal, 14)
              .padding(.vertical, 9)
              .background(selection == filter ? OkkleColor.brand : Color.white.opacity(0.72), in: Capsule())
              .overlay(
                Capsule()
                  .stroke(selection == filter ? OkkleColor.brand : OkkleColor.line, lineWidth: 1)
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

private struct NativeHeatMapView: View {
  let points: [NativeHeatPoint]
  @State private var region = nativeHeatRegion(for: [])

  private var hasEnoughPoints: Bool {
    points.count >= 2 && nativeDistinctCoordinateCount(points) >= 2
  }

  private var signature: String {
    "\(points.count)-\(points.first?.id ?? "none")-\(points.last?.id ?? "none")"
  }

  var body: some View {
    Group {
      if hasEnoughPoints {
        Map(coordinateRegion: $region, annotationItems: nativeHeatBubbles(from: points)) { bubble in
          MapAnnotation(coordinate: bubble.coordinate) {
            Circle()
              .fill(nativeHeatColor(bubble.normalized).opacity(0.42))
              .frame(width: bubble.diameter, height: bubble.diameter)
              .blur(radius: 5)
              .overlay(
                Circle()
                  .stroke(Color.white.opacity(0.20), lineWidth: 1)
              )
              .allowsHitTesting(false)
          }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear(perform: updateRegion)
        .onChange(of: signature) { _ in updateRegion() }
      } else {
        NativeHeatMapEmpty()
      }
    }
  }

  private func updateRegion() {
    region = nativeHeatRegion(for: points)
  }
}

private struct NativeHeatMapEmpty: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "map")
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(OkkleColor.brand)
      Text("Track a few GPS trips and your hotspots will appear here.")
        .font(.system(size: 15, weight: .semibold))
        .multilineTextAlignment(.center)
        .foregroundStyle(OkkleColor.muted)
        .padding(.horizontal, 18)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 220)
    .background(Color(red: 0.94, green: 0.97, blue: 0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
}

private struct NativeHeatLegend: View {
  private let colors = [
    Color(red: 0.61, green: 0.89, blue: 0.82),
    Color(red: 0.37, green: 0.82, blue: 0.73),
    Color(red: 0.91, green: 0.78, blue: 0.42),
    Color(red: 0.88, green: 0.59, blue: 0.12),
    Color(red: 0.89, green: 0.38, blue: 0.29)
  ]

  var body: some View {
    HStack(spacing: 8) {
      Text("Quieter")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      HStack(spacing: 0) {
        ForEach(colors.indices, id: \.self) { index in
          colors[index]
            .frame(maxWidth: .infinity)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 8)
      .clipShape(Capsule())
      Text("Busier")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
  }
}

struct NativeInsightsView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var heatFilter: NativeTimeFilter = .all
  private let weekdays = Calendar.current.shortWeekdaySymbols
  private var selectedHeatPoints: [NativeHeatPoint] {
    nativeHeatPoints(from: store.trips, filter: heatFilter)
  }
  private var hasAnyHeatPoints: Bool {
    !nativeHeatPoints(from: store.trips, filter: .all).isEmpty
  }

  var body: some View {
    NativeScreen(title: "Insights", subtitle: "AI guidance, smart nudges and patterns from your work.") {
      NativeHeatMapCard(points: selectedHeatPoints, showsFilters: hasAnyHeatPoints, filter: $heatFilter)

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
        }
      }

      NativeKeyTaxDatesPanel()

      if store.history.isEmpty {
        NativeEmptyState(symbol: "sparkles", title: "Insights will grow with your data", message: "Track trips and log pay to unlock best zones, hours, platform mix and tax-aware suggestions.")
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

private struct NativeTaxDeadline: Identifiable {
  let title: String
  let month: Int
  let day: Int
  let note: String

  var id: String { title }

  func nextOccurrence(from reference: Date = Date()) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: reference)
    let year = calendar.component(.year, from: reference)
    var components = DateComponents(year: year, month: month, day: day, hour: 9, minute: 0)
    var date = calendar.date(from: components) ?? reference
    if date < today {
      components.year = year + 1
      date = calendar.date(from: components) ?? reference
    }
    return date
  }
}

private let nativeTaxDeadlines = [
  NativeTaxDeadline(title: "Register for Self Assessment", month: 10, day: 5, note: "Only if this was your first year self-employed."),
  NativeTaxDeadline(title: "File your return & pay your tax", month: 1, day: 31, note: "Online Self Assessment deadline for the previous tax year."),
  NativeTaxDeadline(title: "Second payment on account", month: 7, day: 31, note: "Only if HMRC asked you for payments on account.")
]

private func nativeDaysUntil(_ date: Date) -> Int {
  let calendar = Calendar.current
  let today = calendar.startOfDay(for: Date())
  let target = calendar.startOfDay(for: date)
  return calendar.dateComponents([.day], from: today, to: target).day ?? 0
}

private func nativeTaxDateLabel(_ date: Date) -> String {
  date.formatted(.dateTime.day().month(.wide).year())
}

@MainActor
private func nativeAddDeadlineToCalendar(_ deadline: NativeTaxDeadline) async -> Bool {
  let eventStore = EKEventStore()
  do {
    let granted: Bool
    if #available(iOS 17.0, *) {
      granted = try await eventStore.requestFullAccessToEvents()
    } else {
      granted = try await withCheckedThrowingContinuation { continuation in
        eventStore.requestAccess(to: .event) { granted, error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: granted)
          }
        }
      }
    }
    guard granted, let calendar = eventStore.defaultCalendarForNewEvents else { return false }

    let start = deadline.nextOccurrence()
    let end = Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start.addingTimeInterval(1800)
    let event = EKEvent(eventStore: eventStore)
    event.calendar = calendar
    event.title = "HMRC: \(deadline.title)"
    event.startDate = start
    event.endDate = end
    event.notes = deadline.note
    event.addAlarm(EKAlarm(relativeOffset: -60 * 60 * 24 * 7))
    try eventStore.save(event, span: .thisEvent)
    return true
  } catch {
    return false
  }
}

private struct NativeKeyTaxDatesPanel: View {
  @State private var showSheet = false

  var body: some View {
    NativeAiCard {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 10) {
          Image(systemName: "calendar.circle.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(OkkleColor.brand)
            .frame(width: 42, height: 42)
            .background(OkkleColor.brand.opacity(0.14), in: Circle())
          Text("KEY TAX DATES")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.purple)
        }
        Text("Keep HMRC deadlines close")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Review Self Assessment dates and add reminders to your calendar.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
        Button {
          showSheet = true
        } label: {
          HStack {
            Text("View dates")
              .font(.system(size: 16, weight: .bold))
            Spacer()
            Image(systemName: "chevron.up")
              .font(.system(size: 15, weight: .bold))
          }
          .foregroundStyle(Color.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
          .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .sheet(isPresented: $showSheet) {
      NativeKeyTaxDatesSheet()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }
}

private struct NativeKeyTaxDatesSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var alertMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Add these dates to Calendar with a reminder one week before.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)

          NativeGlassCard {
            VStack(spacing: 0) {
              ForEach(nativeTaxDeadlines) { deadline in
                NativeTaxDeadlineRow(deadline: deadline) { message in
                  alertMessage = message
                }
                if deadline.id != nativeTaxDeadlines.last?.id {
                  Divider().padding(.leading, 0)
                }
              }
            }
          }

          Button {
            Task {
              var added = 0
              for deadline in nativeTaxDeadlines {
                if await nativeAddDeadlineToCalendar(deadline) {
                  added += 1
                }
              }
              alertMessage = added == nativeTaxDeadlines.count
                ? "All key tax dates were added to your calendar."
                : "Added \(added) of \(nativeTaxDeadlines.count) dates. Please allow calendar access and try again for the rest."
            }
          } label: {
            Label("Add all dates", systemImage: "calendar.badge.plus")
              .font(.system(size: 16, weight: .bold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 15)
              .foregroundStyle(Color.white)
              .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
          .buttonStyle(.plain)

          Text("Keep your records for at least 5 years after the 31 January deadline. MTD for Income Tax adds quarterly updates once your income passes the threshold.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
      }
      .background(NativeBackground())
      .navigationTitle("Key tax dates")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
      .alert("Calendar", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(alertMessage ?? "")
      }
    }
  }
}

private struct NativeTaxDeadlineRow: View {
  let deadline: NativeTaxDeadline
  let onResult: (String) -> Void
  @State private var busy = false

  var body: some View {
    let next = deadline.nextOccurrence()
    let days = nativeDaysUntil(next)
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(deadline.title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        Text("\(nativeTaxDateLabel(next)) - \(daysLabel(days))")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.brandDark)
        Text(deadline.note)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button {
        busy = true
        Task {
          let ok = await nativeAddDeadlineToCalendar(deadline)
          busy = false
          onResult(ok
            ? "\(deadline.title) was added to your calendar with a reminder one week before."
            : "Could not add \(deadline.title). Please allow calendar access and try again.")
        }
      } label: {
        Label(busy ? "Adding" : "Add", systemImage: "calendar.badge.plus")
          .font(.system(size: 13, weight: .bold))
          .labelStyle(.titleAndIcon)
          .foregroundStyle(OkkleColor.brandDark)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(OkkleColor.brand.opacity(0.13), in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(busy)
    }
    .padding(.vertical, 13)
  }

  private func daysLabel(_ days: Int) -> String {
    if days == 0 { return "today" }
    if days == 1 { return "tomorrow" }
    return "in \(days) days"
  }
}

struct NativeRecordsView: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var mode: RecordsMode = .history
  @State private var filter: RecordsFilter = .all
  @State private var itemPendingDeletion: NativeHistoryItem?

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
                      itemPendingDeletion = item
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
    .alert("Delete this entry?", isPresented: Binding(
      get: { itemPendingDeletion != nil },
      set: { if !$0 { itemPendingDeletion = nil } }
    )) {
      Button("Cancel", role: .cancel) {
        itemPendingDeletion = nil
      }
      Button("Delete", role: .destructive) {
        if let item = itemPendingDeletion {
          delete(item)
        }
        itemPendingDeletion = nil
      }
    } message: {
      Text(pendingDeletionMessage)
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

  private var pendingDeletionMessage: String {
    guard let item = itemPendingDeletion else {
      return "This cannot be undone."
    }
    switch item {
    case .trip:
      return "This trip, route and mileage deduction will be removed from Records. This cannot be undone."
    case .record(let record):
      return "This \(record.kind.label.lowercased()) entry will be removed from Records and tax totals. This cannot be undone."
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

private struct NativeShareItem: Identifiable {
  let id = UUID()
  let url: URL
}

private struct NativeShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum NativeBackupResult {
  case iCloud(URL)
  case share(NativeShareItem)
  case failed(String)
}

@MainActor
private func nativeCreateBackup(store: OkkleStore) -> NativeBackupResult {
  if let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
    do {
      let folder = container
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("Okkle Backups", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

      let url = folder.appendingPathComponent(nativeBackupFileName())
      try store.backupData().write(to: url, options: [.atomic])
      return .iCloud(url)
    } catch {
      if let item = nativeCreateShareBackup(store: store) {
        return .share(item)
      }
      return .failed("Could not write to iCloud Drive. \(error.localizedDescription)")
    }
  }

  if let item = nativeCreateShareBackup(store: store) {
    return .share(item)
  }
  return .failed("iCloud Drive is not available on this device.")
}

@MainActor
private func nativeCreateShareBackup(store: OkkleStore) -> NativeShareItem? {
  do {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(nativeBackupFileName())
    try store.backupData().write(to: url, options: [.atomic])
    return NativeShareItem(url: url)
  } catch {
    return nil
  }
}

private func nativeBackupFileName() -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
  return "Okkle_Backup_\(formatter.string(from: Date())).json"
}

private enum NativeTaxExportKind: String, CaseIterable, Identifiable {
  case accountantPack
  case freeAgent
  case selfAssessment
  case mileageLog
  case allData

  var id: String { rawValue }

  var title: String {
    switch self {
    case .accountantPack: return "Accountant pack"
    case .freeAgent: return "FreeAgent CSV"
    case .selfAssessment: return "Self Assessment summary"
    case .mileageLog: return "HMRC mileage log"
    case .allData: return "All data CSV"
    }
  }

  var subtitle: String {
    switch self {
    case .accountantPack: return "Summary, mileage, expenses and records"
    case .freeAgent: return "Income and expenses for bank import"
    case .selfAssessment: return "Turnover, expenses, profit and tax estimate"
    case .mileageLog: return "GPS and manual mileage claims"
    case .allData: return "Trips, earnings, mileage and expenses"
    }
  }

  var symbol: String {
    switch self {
    case .accountantPack: return "doc.richtext.fill"
    case .freeAgent: return "arrow.up.doc.fill"
    case .selfAssessment: return "doc.text.fill"
    case .mileageLog: return "map.fill"
    case .allData: return "externaldrive.fill"
    }
  }

  var fileStem: String {
    switch self {
    case .accountantPack: return "Accountant-Pack"
    case .freeAgent: return "FreeAgent-Import"
    case .selfAssessment: return "SelfAssessment-Summary"
    case .mileageLog: return "HMRC-Mileage-Log"
    case .allData: return "All-Data"
    }
  }

  var fileExtension: String {
    switch self {
    case .accountantPack, .selfAssessment: return "txt"
    case .freeAgent, .mileageLog, .allData: return "csv"
    }
  }
}

private struct NativeExportCard: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var shareItem: NativeShareItem?
  @State private var exportFailed = false

  var body: some View {
    NativeGlassCard(cornerRadius: 30) {
      VStack(alignment: .leading, spacing: 14) {
        Label("Send to your accountant", systemImage: "square.and.arrow.up")
          .font(.system(size: 16, weight: .heavy))
          .foregroundStyle(OkkleColor.brandDark)
        Text("Export & share")
          .font(.system(size: 24, weight: .heavy, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Generate files on-device and choose where to send or save them.")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(OkkleColor.muted)

        VStack(spacing: 0) {
          ForEach(NativeTaxExportKind.allCases) { kind in
            Button {
              if let item = nativeMakeExport(kind, store: store) {
                shareItem = item
              } else {
                exportFailed = true
              }
            } label: {
              HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                  .font(.system(size: 17, weight: .bold))
                  .foregroundStyle(OkkleColor.brand)
                  .frame(width: 38, height: 38)
                  .background(OkkleColor.brand.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                  Text(kind.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(OkkleColor.ink)
                  Text(kind.subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OkkleColor.muted)
                    .lineLimit(2)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                  .font(.system(size: 15, weight: .bold))
                  .foregroundStyle(OkkleColor.muted)
              }
              .padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            if kind != .allData {
              Divider().padding(.leading, 50)
            }
          }
        }
      }
    }
    .sheet(item: $shareItem) { item in
      NativeShareSheet(items: [item.url])
    }
    .alert("Could not create export", isPresented: $exportFailed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Please try again.")
    }
  }
}

@MainActor
private func nativeMakeExport(_ kind: NativeTaxExportKind, store: OkkleStore) -> NativeShareItem? {
  let content = nativeExportContents(kind, store: store)
  let fileName = "Okkle_\(kind.fileStem)_TaxYear-\(nativeTaxYearLabel(for: store.taxYear))_\(nativeTodayStamp()).\(kind.fileExtension)"
    .replacingOccurrences(of: "/", with: "-")
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
  do {
    try content.write(to: url, atomically: true, encoding: .utf8)
    return NativeShareItem(url: url)
  } catch {
    return nil
  }
}

@MainActor
private func nativeExportContents(_ kind: NativeTaxExportKind, store: OkkleStore) -> String {
  switch kind {
  case .accountantPack:
    return [
      nativeSelfAssessmentText(store: store),
      "",
      "Mileage log",
      nativeMileageCsv(store: store),
      "",
      "All records",
      nativeAllDataCsv(store: store)
    ].joined(separator: "\n")
  case .freeAgent:
    return nativeFreeAgentCsv(store: store)
  case .selfAssessment:
    return nativeSelfAssessmentText(store: store)
  case .mileageLog:
    return nativeMileageCsv(store: store)
  case .allData:
    return nativeAllDataCsv(store: store)
  }
}

@MainActor
private func nativeSelfAssessmentText(store: OkkleStore) -> String {
  let tax = store.taxPosition
  let lines = [
    "Okkle - Self Assessment summary \(nativeTaxYearLabel(for: store.taxYear))",
    "",
    "Turnover (income):        \(gbp(tax.turnover))",
    "Allowable expenses:       \(gbp(tax.expenses))",
    "Net profit:               \(gbp(tax.profit))",
    "",
    "Estimated Income Tax:     \(gbp(tax.incomeTax))",
    "Estimated Class 4 NIC:    \(gbp(tax.class4))",
    "Estimated total due:      \(gbp(tax.totalDue))",
    tax.paymentOnAccount > 0 ? "Payment on account (x2):  \(gbp(tax.paymentOnAccount)) each" : "",
    "",
    "Business miles:           \(miles(store.yearMiles))",
    "Mileage deduction:        \(gbp(store.yearMileageDeduction))",
    "",
    "Estimates only, not tax advice. Confirm with your accountant."
  ]
  return lines.filter { !$0.isEmpty }.joined(separator: "\n")
}

@MainActor
private func nativeMileageCsv(store: OkkleStore) -> String {
  let header = "Date,Vehicle,Source,Miles,Basis,Deduction GBP"
  let tripRows = store.trips.sorted { $0.startedAt < $1.startedAt }.map { trip in
    [
      nativeCsvField(nativeDateStamp(trip.startedAt)),
      nativeCsvField(trip.vehicle.label),
      nativeCsvField("GPS"),
      nativeCsvField(nativeDecimal(trip.miles)),
      nativeCsvField("HMRC simplified"),
      nativeCsvField(nativeDecimal(trip.deduction))
    ].joined(separator: ",")
  }
  let manualRows = store.records
    .filter { $0.kind == .mileage }
    .sorted { $0.date < $1.date }
    .map { record in
      [
        nativeCsvField(nativeDateStamp(record.date)),
        nativeCsvField(record.vehicle?.label ?? "Vehicle"),
        nativeCsvField("Manual"),
        nativeCsvField(nativeDecimal(record.miles ?? 0)),
        nativeCsvField("HMRC simplified"),
        nativeCsvField(nativeDecimal(record.deduction ?? 0))
      ].joined(separator: ",")
    }
  return ([header] + tripRows + manualRows).joined(separator: "\n")
}

@MainActor
private func nativeFreeAgentCsv(store: OkkleStore) -> String {
  let rows = store.records
    .filter { ($0.kind == .income || $0.kind == .expense) && (($0.amount ?? 0) > 0) }
    .sorted { $0.date < $1.date }
    .map { record in
      let amount = record.kind == .expense ? -abs(record.amount ?? 0) : (record.amount ?? 0)
      let description: String
      if record.kind == .income {
        description = "\(record.platform ?? "Platform") earnings"
      } else {
        description = [record.merchant, record.category ?? "Expense"].compactMap { value in
          guard let value, !value.isEmpty else { return nil }
          return value
        }.joined(separator: " - ")
      }
      return [
        nativeCsvField(nativeUkDateStamp(record.date)),
        nativeCsvField(nativeDecimal(amount)),
        nativeCsvField(description)
      ].joined(separator: ",")
    }
  return (["Date,Amount,Description"] + rows).joined(separator: "\n")
}

@MainActor
private func nativeAllDataCsv(store: OkkleStore) -> String {
  let header = "date,type,platform,vehicle,miles,deduction,amount,category,merchant"
  let tripRows = store.trips.map { trip in
    [
      nativeCsvField(nativeDateStamp(trip.startedAt)),
      nativeCsvField("trip"),
      nativeCsvField(""),
      nativeCsvField(trip.vehicle.label),
      nativeCsvField(nativeDecimal(trip.miles)),
      nativeCsvField(nativeDecimal(trip.deduction)),
      nativeCsvField(""),
      nativeCsvField(""),
      nativeCsvField("")
    ].joined(separator: ",")
  }
  let recordRows = store.records.map { record in
    [
      nativeCsvField(nativeDateStamp(record.date)),
      nativeCsvField(record.kind.rawValue),
      nativeCsvField(record.platform ?? ""),
      nativeCsvField(record.vehicle?.label ?? ""),
      nativeCsvField(record.miles.map(nativeDecimal) ?? ""),
      nativeCsvField(record.deduction.map(nativeDecimal) ?? ""),
      nativeCsvField(record.amount.map(nativeDecimal) ?? ""),
      nativeCsvField(record.category ?? ""),
      nativeCsvField(record.merchant ?? "")
    ].joined(separator: ",")
  }
  return ([header] + tripRows + recordRows).joined(separator: "\n")
}

private func nativeCsvField(_ value: String) -> String {
  if value.contains(",") || value.contains("\"") || value.contains("\n") {
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
  return value
}

private func nativeDecimal(_ value: Double) -> String {
  String(format: "%.2f", value)
}

private func nativeTodayStamp() -> String {
  nativeDateStamp(Date())
}

private func nativeDateStamp(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: date)
}

private func nativeUkDateStamp(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_GB")
  formatter.dateFormat = "dd/MM/yyyy"
  return formatter.string(from: date)
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

      NativeExportCard()
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
  @State private var backupBusy = false
  @State private var backupMessage: String?
  @State private var backupShareItem: NativeShareItem?
  @State private var showClearDataWarning = false
  @State private var showDataClearedConfirmation = false

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
          Button {
            backupBusy = true
            switch nativeCreateBackup(store: store) {
            case .iCloud(let url):
              backupMessage = "Backed up to iCloud Drive as \(url.lastPathComponent)."
            case .share(let item):
              backupShareItem = item
            case .failed(let message):
              backupMessage = message
            }
            backupBusy = false
          } label: {
            Label(backupBusy ? "Backing up..." : "Back up to iCloud", systemImage: "icloud.and.arrow.up")
          }
          .disabled(backupBusy)

          Text("Creates a JSON backup in iCloud Drive. If iCloud is not available, Okkle opens the native share sheet so you can save the backup to Files.")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Button(role: .destructive) {
            showClearDataWarning = true
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
      .sheet(item: $backupShareItem) { item in
        NativeShareSheet(items: [item.url])
      }
      .alert("Backup", isPresented: Binding(
        get: { backupMessage != nil },
        set: { if !$0 { backupMessage = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(backupMessage ?? "")
      }
      .alert("Clear records and trips?", isPresented: $showClearDataWarning) {
        Button("Cancel", role: .cancel) {}
        Button("Clear data", role: .destructive) {
          store.resetAllData()
          showDataClearedConfirmation = true
        }
      } message: {
        Text("This permanently deletes every saved trip, earning, expense, mileage entry and route from this device. Create a backup first if you might need the data later.")
      }
      .alert("Data cleared", isPresented: $showDataClearedConfirmation) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("Your records and trips have been removed.")
      }
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
