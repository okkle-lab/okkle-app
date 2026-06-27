import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision

private enum OkkleColor {
  static let brand = Color(red: 0.03, green: 0.58, blue: 0.49)
  static let brandDark = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.44, green: 0.90, blue: 0.80, alpha: 1)
      : UIColor(red: 0.03, green: 0.36, blue: 0.31, alpha: 1)
  })
  static let mint = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.09, green: 0.24, blue: 0.21, alpha: 1)
      : UIColor(red: 0.83, green: 0.97, blue: 0.94, alpha: 1)
  })
  static let ink = Color(uiColor: .label)
  static let muted = Color(uiColor: .secondaryLabel)
  static let line = Color(uiColor: .separator)
  static let amber = Color(red: 0.86, green: 0.50, blue: 0.08)
  static let red = Color(red: 0.82, green: 0.20, blue: 0.18)
  static let blue = Color(red: 0.18, green: 0.39, blue: 0.86)
  static let fieldBackground = Color(uiColor: .secondarySystemBackground).opacity(0.82)
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

private func headlineGbp(_ value: Double) -> String {
  abs(value) < 100 ? gbp(value) : gbp(value, whole: true)
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
  var legacyID: String? = nil
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
  var periodStart: Date? = nil
  var periodEnd: Date? = nil
  var receiptImageData: Data?
}

struct NativeTrip: Identifiable, Codable, Equatable {
  var id = UUID()
  var legacyID: String? = nil
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
  private let legacyMigrationKey = "uk.okkle.native.swiftui.legacySqliteMigration.v1"
  private var isLoading = false

  init() {
    load()
  }

  func load() {
    isLoading = true
    var shouldPersist = false
    defer {
      isLoading = false
      if shouldPersist { save() }
    }

    if let data = UserDefaults.standard.data(forKey: key) {
      do {
        let snapshot = try JSONDecoder().decode(NativeSnapshot.self, from: data)
        settings = snapshot.settings
        records = snapshot.records
        trips = snapshot.trips
      } catch {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }

    if !UserDefaults.standard.bool(forKey: legacyMigrationKey),
       let imported = NativeLegacySQLiteImporter.importSnapshot() {
      merge(imported)
      UserDefaults.standard.set(true, forKey: legacyMigrationKey)
      shouldPersist = true
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

  func updateTrip(_ trip: NativeTrip) {
    guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
    trips[index] = trip
  }

  func updateRecord(_ record: NativeRecord) {
    guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
    records[index] = record
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
    records.filter { recordOverlapsTaxYear($0) }
  }

  var yearTrips: [NativeTrip] {
    trips.filter { taxYear.contains($0.startedAt) }
  }

  var yearMiles: Double {
    yearTrips.reduce(0) { $0 + $1.miles } + yearRecords.reduce(0) { $0 + mileageForTaxYear($1) }
  }

  var yearMileageDeduction: Double {
    yearTrips.reduce(0) { $0 + deduction(for: $1) } + yearRecords.reduce(0) { $0 + deductionForTaxYear($1) }
  }

  var yearIncome: Double {
    yearRecords.reduce(0) { $0 + incomeForTaxYear($1) }
  }

  var yearExpenses: Double {
    yearRecords.reduce(0) { $0 + expenseForTaxYear($1) } + yearMileageDeduction
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

  func periodBounds(for date: Date, period: NativePayPeriod) -> (start: Date, end: Date) {
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: date)
    switch period {
    case .day:
      return (day, day)
    case .week:
      let weekday = calendar.component(.weekday, from: day)
      let mondayOffset = weekday == 1 ? -6 : 2 - weekday
      let start = calendar.date(byAdding: .day, value: mondayOffset, to: day) ?? day
      let end = calendar.date(byAdding: .day, value: 6, to: start) ?? day
      return (start, end)
    }
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

  private func merge(_ imported: NativeLegacyImportResult) {
    if let importedSettings = imported.settings {
      settings = importedSettings
    }

    let existingTripLegacyIDs = Set(trips.compactMap(\.legacyID))
    let newTrips = imported.trips.filter { trip in
      if let legacyID = trip.legacyID, existingTripLegacyIDs.contains(legacyID) {
        return false
      }
      return !trips.contains { likelySameTrip($0, trip) }
    }
    if !newTrips.isEmpty {
      trips = (trips + newTrips).sorted { $0.startedAt > $1.startedAt }
    }

    let existingRecordLegacyIDs = Set(records.compactMap(\.legacyID))
    let newRecords = imported.records.filter { record in
      if let legacyID = record.legacyID, existingRecordLegacyIDs.contains(legacyID) {
        return false
      }
      return !records.contains { likelySameRecord($0, record) }
    }
    if !newRecords.isEmpty {
      records = (records + newRecords).sorted { $0.date > $1.date }
    }
  }

  private func recordInterval(_ record: NativeRecord) -> DateInterval {
    let calendar = Calendar.current
    let bounds: (start: Date, end: Date)
    if let periodStart = record.periodStart, let periodEnd = record.periodEnd {
      bounds = (calendar.startOfDay(for: periodStart), calendar.startOfDay(for: periodEnd))
    } else {
      bounds = periodBounds(for: record.date, period: record.period)
    }
    let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: bounds.end) ?? bounds.end
    return DateInterval(start: bounds.start, end: exclusiveEnd)
  }

  private func likelySameTrip(_ lhs: NativeTrip, _ rhs: NativeTrip) -> Bool {
    lhs.vehicle == rhs.vehicle &&
      abs(lhs.miles - rhs.miles) < 0.01 &&
      abs(lhs.startedAt.timeIntervalSince(rhs.startedAt)) < 60
  }

  private func likelySameRecord(_ lhs: NativeRecord, _ rhs: NativeRecord) -> Bool {
    guard lhs.kind == rhs.kind,
          Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) else {
      return false
    }

    switch lhs.kind {
    case .income:
      return abs((lhs.amount ?? 0) - (rhs.amount ?? 0)) < 0.01 &&
        (lhs.platform ?? "") == (rhs.platform ?? "")
    case .expense:
      return abs((lhs.amount ?? 0) - (rhs.amount ?? 0)) < 0.01 &&
        (lhs.category ?? "") == (rhs.category ?? "")
    case .mileage:
      return lhs.vehicle == rhs.vehicle &&
        abs((lhs.miles ?? 0) - (rhs.miles ?? 0)) < 0.01
    }
  }

  private func recordOverlapsTaxYear(_ record: NativeRecord) -> Bool {
    recordInterval(record).intersects(taxYear)
  }

  private func taxYearShare(for record: NativeRecord) -> Double {
    let interval = recordInterval(record)
    guard interval.duration > 0, let overlap = interval.intersection(with: taxYear) else { return 0 }
    return min(1, max(0, overlap.duration / interval.duration))
  }

  private func mileageForTaxYear(_ record: NativeRecord) -> Double {
    guard record.kind == .mileage else { return 0 }
    return (record.miles ?? 0) * taxYearShare(for: record)
  }

  private func deduction(for trip: NativeTrip) -> Double {
    if trip.deduction > 0 || trip.miles <= 0 { return trip.deduction }
    return calcDeduction(miles: trip.miles, vehicle: trip.vehicle, date: trip.startedAt)
  }

  private func deductionForTaxYear(_ record: NativeRecord) -> Double {
    guard record.kind == .mileage else { return 0 }
    let base = (record.deduction ?? 0) > 0
      ? (record.deduction ?? 0)
      : calcDeduction(miles: record.miles ?? 0, vehicle: record.vehicle ?? settings.defaultVehicle, date: record.date)
    return base * taxYearShare(for: record)
  }

  private func incomeForTaxYear(_ record: NativeRecord) -> Double {
    guard record.kind == .income else { return 0 }
    return (record.amount ?? 0) * taxYearShare(for: record)
  }

  private func expenseForTaxYear(_ record: NativeRecord) -> Double {
    guard record.kind == .expense else { return 0 }
    return (record.amount ?? 0) * taxYearShare(for: record)
  }
}

private struct NativeLegacyImportResult {
  var settings: NativeSettings?
  var records: [NativeRecord]
  var trips: [NativeTrip]
}

private enum NativeLegacySQLiteImporter {
  static func importSnapshot() -> NativeLegacyImportResult? {
    for url in candidateDatabaseURLs() {
      guard FileManager.default.fileExists(atPath: url.path) else { continue }

      var db: OpaquePointer?
      guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
        sqlite3_close(db)
        continue
      }
      defer { sqlite3_close(db) }

      let settings = readSettings(from: db)
      let trips = readTrips(from: db)
      let records = readRecords(from: db)
      if settings != nil || !trips.isEmpty || !records.isEmpty {
        return NativeLegacyImportResult(settings: settings, records: records, trips: trips)
      }
    }
    return nil
  }

  private static func candidateDatabaseURLs() -> [URL] {
    let manager = FileManager.default
    let roots = [
      manager.urls(for: .documentDirectory, in: .userDomainMask).first,
      manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
      manager.urls(for: .libraryDirectory, in: .userDomainMask).first,
    ].compactMap { $0 }

    var urls: [URL] = []
    for root in roots {
      urls.append(root.appendingPathComponent("SQLite", isDirectory: true).appendingPathComponent("okkle.db"))
      if let enumerator = manager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) {
        for case let url as URL in enumerator where url.lastPathComponent == "okkle.db" {
          urls.append(url)
        }
      }
    }

    var seen = Set<String>()
    return urls.filter { url in
      let key = url.standardizedFileURL.path
      guard !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
  }

  private static func readSettings(from db: OpaquePointer) -> NativeSettings? {
    guard let row = rows(from: db, sql: "SELECT * FROM user LIMIT 1").first else { return nil }
    var settings = NativeSettings()
    settings.name = string(row["name"]) ?? ""
    settings.defaultVehicle = vehicle(from: string(row["vehicle"])) ?? .car
    settings.region = NativeRegion(rawValue: string(row["region"]) ?? "") ?? .ruk

    let platforms = splitList(string(row["platforms"]))
    if !platforms.isEmpty {
      settings.platforms = platforms
    }

    if let enabled = int(row["reminder_enabled"]) {
      settings.loggingReminder = enabled != 0
    }
    if let reminderDay = string(row["reminder_day"]) {
      settings.reminderDay = weekdayIndex(from: reminderDay)
    }
    if let frequency = NativeLogFrequency(rawValue: string(row["log_frequency"]) ?? "") {
      settings.logFrequency = frequency
    }

    return settings
  }

  private static func readTrips(from db: OpaquePointer) -> [NativeTrip] {
    rows(from: db, sql: "SELECT * FROM trips").compactMap { row in
      guard let id = int(row["id"]),
            let vehicle = vehicle(from: string(row["vehicle"])),
            let startedAt = date(row["started_at"]),
            let endedAt = date(row["ended_at"]) ?? date(row["started_at"]) else {
        return nil
      }

      let miles = double(row["miles"]) ?? 0
      let storedDeduction = double(row["deduction"]) ?? 0
      return NativeTrip(
        legacyID: "sqlite-trip-\(id)",
        vehicle: vehicle,
        miles: miles,
        deduction: storedDeduction > 0 ? storedDeduction : calculatedDeduction(miles: miles, vehicle: vehicle, date: startedAt),
        startedAt: startedAt,
        endedAt: endedAt,
        points: routePoints(from: string(row["route_json"]))
      )
    }
  }

  private static func readRecords(from db: OpaquePointer) -> [NativeRecord] {
    rows(from: db, sql: "SELECT * FROM records").compactMap { row in
      guard let id = int(row["id"]),
            let kind = NativeLogKind(rawValue: string(row["record_type"]) ?? "") else {
        return nil
      }

      let createdAt = date(row["created_at"]) ?? date(row["period_start"]) ?? Date()
      let periodStart = dateOnly(row["period_start"])
      let periodEnd = dateOnly(row["period_end"])
      let period = periodKind(start: periodStart, end: periodEnd)
      let recordVehicle = vehicle(from: string(row["vehicle"]))
      let miles = double(row["miles"])
      let storedDeduction = double(row["deduction"])
      let deduction: Double?
      if kind == .mileage {
        let vehicle = recordVehicle ?? .car
        let mileage = miles ?? 0
        deduction = (storedDeduction ?? 0) > 0
          ? storedDeduction
          : calculatedDeduction(miles: mileage, vehicle: vehicle, date: createdAt)
      } else {
        deduction = storedDeduction
      }

      return NativeRecord(
        legacyID: "sqlite-record-\(id)",
        kind: kind,
        platform: nonEmpty(string(row["platform"])),
        vehicle: recordVehicle,
        amount: double(row["amount"]),
        miles: miles,
        deduction: deduction,
        category: nonEmpty(string(row["category"]) ?? string(row["notes"])),
        merchant: nil,
        date: createdAt,
        period: period,
        periodStart: periodStart,
        periodEnd: periodEnd,
        receiptImageData: receiptData(from: string(row["receipt_uri"]))
      )
    }
  }

  private static func rows(from db: OpaquePointer, sql: String) -> [[String: String?]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      sqlite3_finalize(statement)
      return []
    }
    defer { sqlite3_finalize(statement) }

    let columnCount = sqlite3_column_count(statement)
    var result: [[String: String?]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      var row: [String: String?] = [:]
      for index in 0..<columnCount {
        guard let namePointer = sqlite3_column_name(statement, index) else { continue }
        let name = String(cString: namePointer)
        if sqlite3_column_type(statement, index) == SQLITE_NULL {
          row[name] = nil
        } else if let textPointer = sqlite3_column_text(statement, index) {
          row[name] = String(cString: textPointer)
        }
      }
      result.append(row)
    }
    return result
  }

  private static func routePoints(from raw: String?) -> [RoutePoint] {
    guard let raw,
          let data = raw.data(using: .utf8),
          let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }

    return values.compactMap { value in
      let latitude = value["lat"] as? Double ?? value["latitude"] as? Double
      let longitude = value["lng"] as? Double ?? value["longitude"] as? Double
      guard let latitude, let longitude else { return nil }
      return RoutePoint(latitude: latitude, longitude: longitude)
    }
  }

  private static func receiptData(from raw: String?) -> Data? {
    guard let raw = nonEmpty(raw) else { return nil }
    let url: URL
    if raw.hasPrefix("file://"), let parsed = URL(string: raw) {
      url = parsed
    } else {
      url = URL(fileURLWithPath: raw)
    }
    return try? Data(contentsOf: url)
  }

  private static func string(_ value: String??) -> String? {
    guard let value = value ?? nil else { return nil }
    return value
  }

  private static func nonEmpty(_ value: String?) -> String? {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return clean.isEmpty ? nil : clean
  }

  private static func double(_ value: String??) -> Double? {
    guard let value = string(value) else { return nil }
    return Double(value)
  }

  private static func int(_ value: String??) -> Int? {
    guard let value = string(value) else { return nil }
    return Int(value)
  }

  private static func splitList(_ raw: String?) -> [String] {
    var seen = Set<String>()
    return (raw ?? "")
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { value in
        guard !value.isEmpty else { return false }
        let key = value.lowercased()
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
      }
  }

  private static func weekdayIndex(from raw: String) -> Int {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    return names.firstIndex { value.hasPrefix($0) } ?? 1
  }

  private static func vehicle(from raw: String?) -> NativeVehicle? {
    switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "car", "auto":
      return .car
    case "motorbike", "motorcycle", "scooter", "moped":
      return .motorbike
    case "bike", "bicycle", "cycle", "e-bike", "ebike":
      return .bike
    case "van":
      return .van
    default:
      return nil
    }
  }

  private static func periodKind(start: Date?, end: Date?) -> NativePayPeriod {
    guard let start, let end else { return .day }
    let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    return days >= 1 ? .week : .day
  }

  private static func calculatedDeduction(miles: Double, vehicle: NativeVehicle, date: Date) -> Double {
    let band = vehicle.rateBand(on: date)
    return miles * band.first
  }

  private static func date(_ value: String??) -> Date? {
    guard let raw = nonEmpty(string(value)) else { return nil }
    return date(from: raw)
  }

  private static func date(from raw: String) -> Date? {
    if let parsed = legacyISOFormatter.date(from: raw) {
      return parsed
    }

    if let parsed = legacyFractionalISOFormatter.date(from: raw) {
      return parsed
    }
    if let parsed = legacyISOFormatter.date(from: raw.replacingOccurrences(of: " ", with: "T") + "Z") {
      return parsed
    }
    if let parsed = legacyFractionalISOFormatter.date(from: raw.replacingOccurrences(of: " ", with: "T") + "Z") {
      return parsed
    }
    if let parsed = legacySQLiteDateTimeFormatter.date(from: raw) {
      return parsed
    }
    return legacyDateOnlyFormatter.date(from: String(raw.prefix(10)))
  }

  private static func dateOnly(_ value: String??) -> Date? {
    guard let raw = nonEmpty(string(value)) else { return nil }
    return legacyDateOnlyFormatter.date(from: String(raw.prefix(10))) ?? date(from: raw)
  }

  private static let legacyISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static let legacyFractionalISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let legacySQLiteDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
  }()

  private static let legacyDateOnlyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
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

  var trip: NativeTrip? {
    if case .trip(let trip) = self { return trip }
    return nil
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

  var titleColor: Color {
    OkkleColor.ink
  }

  var subtitleColor: Color {
    OkkleColor.muted
  }

  var settingsColor: Color {
    OkkleColor.ink
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
      .background { NativeBackground() }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.large)
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
      colors: [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
  }
}

struct NativeGlassCard<Content: View>: View {
  var cornerRadius: CGFloat = 26
  var contentPadding: CGFloat = 20
  var content: Content

  init(cornerRadius: CGFloat = 26, contentPadding: CGFloat = 20, @ViewBuilder content: () -> Content) {
    self.cornerRadius = cornerRadius
    self.contentPadding = contentPadding
    self.content = content()
  }

  var body: some View {
    content
      .padding(contentPadding)
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
      .background(OkkleColor.fieldBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke((focused || expanded) ? OkkleColor.brand.opacity(0.45) : OkkleColor.line, lineWidth: 1)
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
            .stroke(OkkleColor.line, lineWidth: 1)
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
          Text(headlineGbp(store.taxSaved))
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
  private var lastRoutePointLocation: CLLocation?
  private var startedAt: Date?
  private var timer: Timer?
  private var waitingForAuthorization = false
  private let routePointDistance: CLLocationDistance = 30
  private let timerInterval: TimeInterval = 5

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    manager.distanceFilter = 20
    manager.activityType = .automotiveNavigation
    manager.pausesLocationUpdatesAutomatically = true
  }

  func start(vehicle: NativeVehicle) {
    self.vehicle = vehicle
    configureLocationManager(for: vehicle)
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
    lastRoutePointLocation = nil
    startedAt = Date()
    phase = .live
    setBackgroundTrackingEnabled(true)
    manager.startUpdatingLocation()
    startTimer()
    waitingForAuthorization = false
  }

  func pause() {
    guard phase == .live else { return }
    phase = .paused
    manager.stopUpdatingLocation()
    setBackgroundTrackingEnabled(false)
    stopTimer()
  }

  func resume() {
    guard phase == .paused else { return }
    phase = .live
    setBackgroundTrackingEnabled(true)
    manager.startUpdatingLocation()
    startTimer()
  }

  @MainActor
  func end(store: OkkleStore) -> NativeTrip? {
    guard let startedAt else { return nil }
    manager.stopUpdatingLocation()
    setBackgroundTrackingEnabled(false)
    stopTimer()
    phase = .summary
    if let lastLocation {
      appendRoutePoint(for: lastLocation, force: true)
    }
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
    setBackgroundTrackingEnabled(false)
    stopTimer()
    waitingForAuthorization = false
    miles = 0
    elapsed = 0
    points = []
    lastLocation = nil
    lastRoutePointLocation = nil
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
      appendRoutePoint(for: location)
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
    timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
      guard let self, let startedAt = self.startedAt else { return }
      self.elapsed = Date().timeIntervalSince(startedAt)
    }
    timer?.tolerance = 2
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func configureLocationManager(for vehicle: NativeVehicle) {
    manager.activityType = vehicle == .bike ? .fitness : .automotiveNavigation
  }

  private func setBackgroundTrackingEnabled(_ enabled: Bool) {
    guard supportsBackgroundLocation else { return }
    manager.allowsBackgroundLocationUpdates = enabled
    manager.showsBackgroundLocationIndicator = enabled
  }

  private var supportsBackgroundLocation: Bool {
    let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
    return backgroundModes.contains("location")
  }

  private func appendRoutePoint(for location: CLLocation, force: Bool = false) {
    if let lastRoutePointLocation {
      let distance = location.distance(from: lastRoutePointLocation)
      guard force ? distance > 1 : distance >= routePointDistance else { return }
    }
    points.append(RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    lastRoutePointLocation = location
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
          .tint(OkkleColor.brand)

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
              .background(OkkleColor.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
          }

          if session.phase != .setup {
            tripControls
          }
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

private struct NativeHistoryDetailSheet: View {
  let item: NativeHistoryItem

  var body: some View {
    switch item {
    case .trip(let trip):
      NativeTripDetailSheet(trip: trip)
    case .record(let record):
      NativeRecordDetailSheet(record: record)
    }
  }
}

private struct NativeTripDetailSheet: View {
  let trip: NativeTrip
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if hasMapDetails {
            NativeRouteMapView(points: trip.points)
              .frame(height: 280)
              .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                  .stroke(.white.opacity(0.68), lineWidth: 1)
              )
          }

          HStack(spacing: 12) {
            NativeMetricTile(title: "Miles", value: miles(trip.miles), symbol: "road.lanes")
            NativeMetricTile(title: "Deduction", value: gbp(trip.deduction, whole: true), symbol: "sterlingsign.circle.fill", color: .green)
          }

          NativeGlassCard {
            VStack(alignment: .leading, spacing: 14) {
              tripDetailRow("Vehicle", value: trip.vehicle.label, symbol: trip.vehicle.symbol)
              Divider()
              tripDetailRow("Started", value: trip.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()), symbol: "play.circle")
              tripDetailRow("Ended", value: trip.endedAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()), symbol: "stop.circle")
              tripDetailRow("Duration", value: nativeDurationLabel(trip.endedAt.timeIntervalSince(trip.startedAt)), symbol: "timer")
            }
          }

          if hasMapDetails {
            NativeGlassCard {
              VStack(alignment: .leading, spacing: 14) {
                Label("Map details", systemImage: "map.fill")
                  .font(.system(size: 16, weight: .bold))
                  .foregroundStyle(OkkleColor.ink)
                if let startPoint {
                  tripDetailRow("Start location", value: coordinateLabel(startPoint), symbol: "location.circle")
                }
                if let endPoint {
                  tripDetailRow("End location", value: coordinateLabel(endPoint), symbol: "mappin.circle")
                }
                tripDetailRow("Route points", value: "\(trip.points.count)", symbol: "point.3.connected.trianglepath.dotted")
              }
            }
          }
        }
        .padding(22)
      }
      .background(NativeBackground())
      .navigationTitle("Trip details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
    }
  }

  private var hasMapDetails: Bool {
    !trip.points.isEmpty
  }

  private var startPoint: RoutePoint? {
    trip.points.first
  }

  private var endPoint: RoutePoint? {
    trip.points.last
  }

  private func coordinateLabel(_ point: RoutePoint) -> String {
    String(format: "%.5f, %.5f", point.latitude, point.longitude)
  }

  private func tripDetailRow(_ title: String, value: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(OkkleColor.brand)
        .frame(width: 34, height: 34)
        .background(OkkleColor.brand.opacity(0.13), in: Circle())
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Spacer()
      Text(value)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
        .multilineTextAlignment(.trailing)
    }
  }
}

private struct NativeRecordDetailSheet: View {
  let record: NativeRecord
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          NativeGlassCard(cornerRadius: 30) {
            HStack(alignment: .center, spacing: 14) {
              Image(systemName: record.kind.symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.14), in: Circle())
              VStack(alignment: .leading, spacing: 4) {
                Text(title)
                  .font(.system(size: 24, weight: .bold, design: .rounded))
                  .foregroundStyle(OkkleColor.ink)
                Text(subtitle)
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(OkkleColor.muted)
              }
              Spacer(minLength: 10)
              Text(primaryValue)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(OkkleColor.ink)
                .minimumScaleFactor(0.7)
            }
          }

          NativeGlassCard {
            VStack(alignment: .leading, spacing: 14) {
              recordDetailRow("Date", value: record.date.formatted(.dateTime.weekday(.abbreviated).day().month().year()), symbol: "calendar")
              recordDetailRow("Period", value: record.period.label, symbol: "calendar.badge.clock")
              Divider()
              detailRows
            }
          }

          if let image = receiptImage {
            NativeGlassCard {
              VStack(alignment: .leading, spacing: 12) {
                Label("Receipt", systemImage: "photo")
                  .font(.system(size: 16, weight: .bold))
                  .foregroundStyle(OkkleColor.ink)
                Image(uiImage: image)
                  .resizable()
                  .scaledToFill()
                  .frame(height: 220)
                  .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
              }
            }
          }
        }
        .padding(22)
      }
      .background(NativeBackground())
      .navigationTitle("Log details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
    }
  }

  @ViewBuilder
  private var detailRows: some View {
    switch record.kind {
    case .income:
      recordDetailRow("Platform", value: record.platform ?? "Earnings", symbol: "app.badge")
      recordDetailRow("Amount", value: gbp(record.amount ?? 0), symbol: "sterlingsign.circle")
    case .expense:
      recordDetailRow("Category", value: record.category ?? "Expense", symbol: "tag")
      if let merchant = record.merchant, !merchant.isEmpty {
        recordDetailRow("Merchant", value: merchant, symbol: "building.2")
      }
      recordDetailRow("Amount", value: gbp(record.amount ?? 0), symbol: "receipt")
    case .mileage:
      recordDetailRow("Vehicle", value: record.vehicle?.label ?? "Vehicle", symbol: record.vehicle?.symbol ?? "car.fill")
      recordDetailRow("Miles", value: miles(record.miles ?? 0), symbol: "road.lanes")
      recordDetailRow("Deduction", value: gbp(record.deduction ?? 0, whole: true), symbol: "sterlingsign.circle")
    }
  }

  private var title: String {
    switch record.kind {
    case .income: return record.platform ?? "Earnings"
    case .expense: return record.category ?? "Expense"
    case .mileage: return "Mileage"
    }
  }

  private var subtitle: String {
    switch record.kind {
    case .income: return "Earnings"
    case .expense:
      if let merchant = record.merchant, !merchant.isEmpty {
        return merchant
      }
      return "Expense"
    case .mileage:
      return record.vehicle?.label ?? "Vehicle"
    }
  }

  private var primaryValue: String {
    switch record.kind {
    case .income, .expense:
      return gbp(record.amount ?? 0)
    case .mileage:
      return miles(record.miles ?? 0)
    }
  }

  private var tint: Color {
    switch record.kind {
    case .income: return .green
    case .expense: return OkkleColor.amber
    case .mileage: return OkkleColor.brand
    }
  }

  private var receiptImage: UIImage? {
    guard let data = record.receiptImageData else { return nil }
    return UIImage(data: data)
  }

  private func recordDetailRow(_ title: String, value: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 34, height: 34)
        .background(tint.opacity(0.13), in: Circle())
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Spacer()
      Text(value)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(OkkleColor.ink)
        .multilineTextAlignment(.trailing)
    }
  }
}

private struct NativeRecordEditSheet: View {
  let record: NativeRecord
  let onSave: (NativeRecord) -> Void
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: OkkleStore
  @State private var amountText: String
  @State private var milesText: String
  @State private var platform: String
  @State private var vehicle: NativeVehicle
  @State private var category: String
  @State private var merchant: String
  @State private var date: Date
  @State private var period: NativePayPeriod
  @FocusState private var focusedField: Field?

  private enum Field {
    case amount
    case miles
  }

  init(record: NativeRecord, onSave: @escaping (NativeRecord) -> Void) {
    self.record = record
    self.onSave = onSave
    _amountText = State(initialValue: record.amount.map { String(format: "%.2f", $0) } ?? "")
    _milesText = State(initialValue: record.miles.map { String(format: "%.1f", $0) } ?? "")
    _platform = State(initialValue: record.platform ?? "Uber Eats")
    _vehicle = State(initialValue: record.vehicle ?? .car)
    _category = State(initialValue: record.category ?? "")
    _merchant = State(initialValue: record.merchant ?? "")
    _date = State(initialValue: record.date)
    _period = State(initialValue: record.period)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(record.kind.label) {
          switch record.kind {
          case .income:
            TextField("Amount", text: $amountText)
              .keyboardType(.decimalPad)
              .focused($focusedField, equals: .amount)
            Picker("Platform", selection: $platform) {
              ForEach(platformOptions, id: \.self) { item in
                Text(item).tag(item)
              }
            }
          case .expense:
            TextField("Amount", text: $amountText)
              .keyboardType(.decimalPad)
              .focused($focusedField, equals: .amount)
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
          case .mileage:
            TextField("Miles", text: $milesText)
              .keyboardType(.decimalPad)
              .focused($focusedField, equals: .miles)
            Picker("Vehicle", selection: $vehicle) {
              ForEach(NativeVehicle.allCases) { item in
                Label(item.label, systemImage: item.symbol).tag(item)
              }
            }
          }
        }

        Section("Date") {
          DatePicker("Date", selection: $date, displayedComponents: .date)
          Picker("Period", selection: $period) {
            ForEach(NativePayPeriod.allCases) { item in
              Text(item.label).tag(item)
            }
          }
        }

        if record.kind == .mileage {
          Section("Preview") {
            HStack {
              Text("Deduction")
              Spacer()
              Text(gbp(previewDeduction, whole: true))
                .fontWeight(.bold)
            }
          }
        }

        if let receiptImage {
          Section("Receipt") {
            Image(uiImage: receiptImage)
              .resizable()
              .scaledToFill()
              .frame(height: 170)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
        }
      }
      .navigationTitle("Edit log")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            save()
          }
          .fontWeight(.bold)
          .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { hideKeyboard() }
            .fontWeight(.bold)
        }
      }
    }
  }

  private var platformOptions: [String] {
    uniqueStrings([platform] + store.settings.platforms)
  }

  private var categoryOptions: [String] {
    let recent = store.records
      .filter { $0.kind == .expense }
      .compactMap { $0.category }
    return uniqueStrings([category] + recent + nativeExpenseCategories)
  }

  private var merchantOptions: [String] {
    let recent = store.records
      .filter { $0.kind == .expense }
      .compactMap { $0.merchant }
    return uniqueStrings([merchant] + recent)
  }

  private var amountValue: Double {
    Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
  }

  private var milesValue: Double {
    Double(milesText.replacingOccurrences(of: ",", with: ".")) ?? 0
  }

  private var previewDeduction: Double {
    store.calcDeduction(miles: milesValue, vehicle: vehicle, date: date)
  }

  private var canSave: Bool {
    switch record.kind {
    case .income:
      return amountValue > 0
    case .expense:
      return amountValue > 0 && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .mileage:
      return milesValue > 0
    }
  }

  private var receiptImage: UIImage? {
    guard let data = record.receiptImageData else { return nil }
    return UIImage(data: data)
  }

  private func save() {
    guard canSave else { return }
    var updated = record
    let bounds = store.periodBounds(for: date, period: period)
    updated.date = date
    updated.period = period
    updated.periodStart = bounds.start
    updated.periodEnd = bounds.end

    switch record.kind {
    case .income:
      updated.platform = platform
      updated.amount = amountValue
    case .expense:
      let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
      let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
      updated.amount = amountValue
      updated.category = cleanCategory
      updated.merchant = cleanMerchant.isEmpty ? nil : cleanMerchant
    case .mileage:
      updated.vehicle = vehicle
      updated.miles = milesValue
      updated.deduction = previewDeduction
    }

    onSave(updated)
    dismiss()
  }
}

private struct NativeTripEditSheet: View {
  let trip: NativeTrip
  let onSave: (NativeTrip) -> Void
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: OkkleStore
  @State private var vehicle: NativeVehicle
  @State private var milesText: String
  @State private var startedAt: Date
  @State private var endedAt: Date
  @FocusState private var milesFocused: Bool

  init(trip: NativeTrip, onSave: @escaping (NativeTrip) -> Void) {
    self.trip = trip
    self.onSave = onSave
    _vehicle = State(initialValue: trip.vehicle)
    _milesText = State(initialValue: String(format: "%.1f", trip.miles))
    _startedAt = State(initialValue: trip.startedAt)
    _endedAt = State(initialValue: trip.endedAt)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Trip") {
          Picker("Vehicle", selection: $vehicle) {
            ForEach(NativeVehicle.allCases) { item in
              Label(item.label, systemImage: item.symbol).tag(item)
            }
          }

          TextField("Miles", text: $milesText)
            .keyboardType(.decimalPad)
            .focused($milesFocused)
        }

        Section("Time") {
          DatePicker("Started", selection: $startedAt)
          DatePicker("Ended", selection: $endedAt)
        }

        Section("Preview") {
          HStack {
            Text("Deduction")
            Spacer()
            Text(gbp(previewDeduction, whole: true))
              .fontWeight(.bold)
          }
          Text("Editing keeps the saved route points and recalculates the mileage deduction.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Edit trip")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            save()
          }
          .fontWeight(.bold)
          .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { hideKeyboard() }
            .fontWeight(.bold)
        }
      }
    }
  }

  private var milesValue: Double {
    Double(milesText.replacingOccurrences(of: ",", with: ".")) ?? 0
  }

  private var canSave: Bool {
    milesValue > 0 && endedAt >= startedAt
  }

  private var previewDeduction: Double {
    store.calcDeduction(miles: milesValue, vehicle: vehicle, date: startedAt)
  }

  private func save() {
    guard canSave else { return }
    var updated = trip
    updated.vehicle = vehicle
    updated.miles = milesValue
    updated.startedAt = startedAt
    updated.endedAt = endedAt
    updated.deduction = previewDeduction
    onSave(updated)
    dismiss()
  }
}

private struct NativeRouteMapView: UIViewRepresentable {
  let points: [RoutePoint]

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.pointOfInterestFilter = .excludingAll
    mapView.showsCompass = false
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    mapView.removeOverlays(mapView.overlays)
    mapView.removeAnnotations(mapView.annotations)

    let coordinates = points.map(\.coordinate)
    guard let first = coordinates.first else {
      mapView.setRegion(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
      ), animated: false)
      return
    }

    let startAnnotation = MKPointAnnotation()
    startAnnotation.coordinate = first
    startAnnotation.title = "Start"
    mapView.addAnnotation(startAnnotation)

    if let last = coordinates.last, coordinates.count > 1 {
      let endAnnotation = MKPointAnnotation()
      endAnnotation.coordinate = last
      endAnnotation.title = "End"
      mapView.addAnnotation(endAnnotation)

      let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
      mapView.addOverlay(polyline)
      mapView.setVisibleMapRect(
        polyline.boundingMapRect,
        edgePadding: UIEdgeInsets(top: 38, left: 30, bottom: 38, right: 30),
        animated: false
      )
    } else {
      mapView.setRegion(MKCoordinateRegion(center: first, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)), animated: false)
    }
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      guard let polyline = overlay as? MKPolyline else {
        return MKOverlayRenderer(overlay: overlay)
      }
      let renderer = MKPolylineRenderer(polyline: polyline)
      renderer.strokeColor = UIColor(red: 0.03, green: 0.58, blue: 0.49, alpha: 1)
      renderer.lineWidth = 5
      renderer.lineCap = .round
      renderer.lineJoin = .round
      return renderer
    }
  }
}

private func nativeDurationLabel(_ seconds: TimeInterval) -> String {
  let total = max(0, Int(seconds))
  let hours = total / 3600
  let minutes = (total % 3600) / 60
  if hours > 0 { return "\(hours)h \(minutes)m" }
  return "\(minutes)m"
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
              .background(selection == filter ? OkkleColor.brand : OkkleColor.fieldBackground, in: Capsule())
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
  @State private var selectedHistoryItem: NativeHistoryItem?
  @State private var tripPendingEdit: NativeTrip?
  @State private var recordPendingEdit: NativeRecord?

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
          NativeGlassCard(contentPadding: 0) {
            VStack(spacing: 0) {
              ForEach(filteredHistory) { item in
                NativeEditableHistoryRow(
                  item: item,
                  onSelect: { selectedHistoryItem = item },
                  onEdit: { edit(item) },
                  onDelete: { itemPendingDeletion = item }
                )
                if item.id != filteredHistory.last?.id {
                  Divider().padding(.leading, 70)
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
    .sheet(item: $selectedHistoryItem) { item in
      NativeHistoryDetailSheet(item: currentItem(matching: item) ?? item)
    }
    .sheet(item: $tripPendingEdit) { trip in
      NativeTripEditSheet(trip: currentTrip(matching: trip) ?? trip) { updatedTrip in
        store.updateTrip(updatedTrip)
        tripPendingEdit = nil
      }
    }
    .sheet(item: $recordPendingEdit) { record in
      NativeRecordEditSheet(record: currentRecord(matching: record) ?? record) { updatedRecord in
        store.updateRecord(updatedRecord)
        recordPendingEdit = nil
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
      if tripPendingEdit?.id == trip.id {
        tripPendingEdit = nil
      }
    case .record(let record):
      store.deleteRecord(record)
      if recordPendingEdit?.id == record.id {
        recordPendingEdit = nil
      }
    }
    if selectedHistoryItem?.id == item.id {
      selectedHistoryItem = nil
    }
  }

  private func edit(_ item: NativeHistoryItem) {
    switch item {
    case .trip(let trip):
      tripPendingEdit = currentTrip(matching: trip) ?? trip
    case .record(let record):
      recordPendingEdit = currentRecord(matching: record) ?? record
    }
  }

  private func currentTrip(matching trip: NativeTrip) -> NativeTrip? {
    store.trips.first { $0.id == trip.id }
  }

  private func currentRecord(matching record: NativeRecord) -> NativeRecord? {
    store.records.first { $0.id == record.id }
  }

  private func currentItem(matching item: NativeHistoryItem) -> NativeHistoryItem? {
    switch item {
    case .trip(let trip):
      return store.trips.first { $0.id == trip.id }.map(NativeHistoryItem.trip)
    case .record(let record):
      return store.records.first { $0.id == record.id }.map(NativeHistoryItem.record)
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

private struct NativeEditableHistoryRow: View {
  let item: NativeHistoryItem
  let onSelect: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void
  @State private var isOpen = false
  @State private var dragOffset: CGFloat = 0

  private let actionWidth: CGFloat = 156
  private let rowHeight: CGFloat = 82

  var body: some View {
    ZStack(alignment: .trailing) {
      HStack(spacing: 0) {
        actionButton(title: "Edit", symbol: "pencil", color: OkkleColor.blue) {
          close()
          onEdit()
        }
        actionButton(title: "Delete", symbol: "trash", color: OkkleColor.red) {
          close()
          onDelete()
        }
      }
      .frame(width: actionWidth, height: rowHeight)
      .opacity(rowOffset < -2 ? 1 : 0)
      .allowsHitTesting(isOpen)
      .frame(maxWidth: .infinity, alignment: .trailing)

      NativeHistoryRow(item: item)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .offset(x: rowOffset)
        .gesture(dragGesture)
        .highPriorityGesture(TapGesture().onEnded {
          if isOpen {
            close()
          } else {
            onSelect()
          }
        })
    }
    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
    .clipped()
    .contextMenu {
      Button(action: onEdit) {
        Label("Edit", systemImage: "pencil")
      }
      Button(role: .destructive, action: onDelete) {
        Label("Delete", systemImage: "trash")
      }
    }
    .accessibilityAddTraits(.isButton)
    .accessibilityHint("Opens details. Swipe left to edit or delete.")
  }

  private var rowBackground: Color {
    Color(uiColor: .secondarySystemGroupedBackground)
  }

  private var rowOffset: CGFloat {
    min(0, max(-actionWidth, (isOpen ? -actionWidth : 0) + dragOffset))
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 16)
      .onChanged { value in
        dragOffset = value.translation.width
      }
      .onEnded { value in
        let finalOffset = min(0, max(-actionWidth, (isOpen ? -actionWidth : 0) + value.translation.width))
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
          isOpen = finalOffset < -actionWidth / 2
          dragOffset = 0
        }
      }
  }

  private func close() {
    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
      isOpen = false
      dragOffset = 0
    }
  }

  private func actionButton(title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .bold))
        Text(title)
          .font(.system(size: 11, weight: .bold))
      }
      .foregroundStyle(.white)
      .frame(width: actionWidth / 2, height: rowHeight)
      .background(color)
    }
    .buttonStyle(.plain)
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
    case .accountantPack: return "Accountant pack PDF"
    case .freeAgent: return "FreeAgent CSV"
    case .selfAssessment: return "Self Assessment summary"
    case .mileageLog: return "HMRC mileage log"
    case .allData: return "All data CSV"
    }
  }

  var subtitle: String {
    switch self {
    case .accountantPack: return "Summary, mileage, expenses, receipts and records"
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
    case .accountantPack: return "pdf"
    case .selfAssessment: return "txt"
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
  let fileName = "Okkle_\(kind.fileStem)_TaxYear-\(nativeTaxYearLabel(for: store.taxYear))_\(nativeTodayStamp()).\(kind.fileExtension)"
    .replacingOccurrences(of: "/", with: "-")
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
  do {
    if kind == .accountantPack {
      try nativeAccountantPackPdfData(store: store).write(to: url, options: [.atomic])
    } else {
      let content = nativeExportContents(kind, store: store)
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
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

@MainActor
private func nativeAccountantPackPdfData(store: OkkleStore) -> Data {
  NativeAccountantPackPdfRenderer(store: store).render()
}

@MainActor
private final class NativeAccountantPackPdfRenderer {
  private let store: OkkleStore
  private let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
  private let margin: CGFloat = 42
  private let ink = UIColor(red: 0.10, green: 0.16, blue: 0.14, alpha: 1)
  private let muted = UIColor(red: 0.42, green: 0.48, blue: 0.45, alpha: 1)
  private let brand = UIColor(red: 0.03, green: 0.58, blue: 0.49, alpha: 1)
  private let pale = UIColor(red: 0.94, green: 0.98, blue: 0.97, alpha: 1)
  private let line = UIColor(red: 0.84, green: 0.88, blue: 0.86, alpha: 1)
  private var y: CGFloat = 42
  private var page = 0
  private var context: UIGraphicsPDFRendererContext?

  init(store: OkkleStore) {
    self.store = store
  }

  func render() -> Data {
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [
      kCGPDFContextTitle as String: "Okkle Accountant Pack \(nativeTaxYearLabel(for: store.taxYear))",
      kCGPDFContextCreator as String: "Okkle"
    ]
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
    return renderer.pdfData { rendererContext in
      context = rendererContext
      beginPage()
      drawCover()
      drawBasis()
      drawSelfAssessment()
      drawIncome()
      drawMileage()
      drawExpenses()
      drawReceipts()
      drawLimitations()
    }
  }

  private var contentWidth: CGFloat {
    pageRect.width - (margin * 2)
  }

  private var bottomLimit: CGFloat {
    pageRect.height - margin - 26
  }

  private var taxYearEndDate: Date {
    Calendar.current.date(byAdding: .day, value: -1, to: store.taxYear.end) ?? store.taxYear.end
  }

  private var yearTrips: [NativeTrip] {
    store.yearTrips.sorted { $0.startedAt < $1.startedAt }
  }

  private var yearRecords: [NativeRecord] {
    store.yearRecords.sorted { $0.date < $1.date }
  }

  private var incomeRecords: [NativeRecord] {
    yearRecords.filter { $0.kind == .income }
  }

  private var expenseRecords: [NativeRecord] {
    yearRecords.filter { $0.kind == .expense }
  }

  private var manualMileageRecords: [NativeRecord] {
    yearRecords.filter { $0.kind == .mileage }
  }

  private func beginPage() {
    context?.beginPage()
    page += 1
    y = margin
    drawFooter()
  }

  private func drawFooter() {
    let text = "Okkle accountant pack - Page \(page)"
    drawString(
      text,
      in: CGRect(x: margin, y: pageRect.height - margin + 4, width: contentWidth, height: 14),
      font: .systemFont(ofSize: 8, weight: .medium),
      color: muted,
      alignment: .center
    )
  }

  private func ensure(_ height: CGFloat) {
    if y + height > bottomLimit {
      beginPage()
    }
  }

  private func drawCover() {
    brand.setFill()
    UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: 86, height: 5), cornerRadius: 2.5).fill()
    y += 20

    drawWrapped("Accountant Review Pack", font: .systemFont(ofSize: 27, weight: .heavy), color: ink, spacingAfter: 4)
    drawWrapped("Income, expenses, mileage and receipt evidence", font: .systemFont(ofSize: 14, weight: .semibold), color: muted, spacingAfter: 13)

    let clientName = store.settings.name.isEmpty ? "Courier" : store.settings.name
    drawWrapped("\(clientName) - Sole trader delivery records", font: .systemFont(ofSize: 12, weight: .medium), color: ink, spacingAfter: 18)

    drawInfoBox([
      ("Accounting period", "\(nativeUkDateStamp(store.taxYear.start)) to \(nativeUkDateStamp(taxYearEndDate))"),
      ("Tax year", nativeTaxYearLabel(for: store.taxYear)),
      ("Prepared", nativeLongDate(Date())),
      ("Tax region", store.settings.region.label)
    ])

    drawWrapped(
      "A review pack to support your accountant. Figures are generated on-device from records logged in Okkle and should be confirmed before filing.",
      font: .systemFont(ofSize: 10.5, weight: .regular),
      color: muted,
      spacingAfter: 14
    )
  }

  private func drawBasis() {
    drawSectionTitle("Basis of preparation")
    drawKeyValue("Accounting basis", "Cash basis")
    drawKeyValue("Mileage method", "Simplified mileage using HMRC flat rates")
    drawKeyValue("Records source", "Tracked trips and manual entries logged in Okkle")
    drawKeyValue("Income entries", "\(incomeRecords.count)")
    drawKeyValue("Expense entries", "\(expenseRecords.count) (\(expenseRecords.filter { $0.receiptImageData != nil }.count) with receipts)")
    drawKeyValue("Mileage entries", "\(yearTrips.count) tracked trips, \(manualMileageRecords.count) manual entries")
  }

  private func drawSelfAssessment() {
    let tax = store.taxPosition
    drawSectionTitle("Self Assessment summary")
    drawTable(
      headers: ["SA103S box", "Description", "Amount"],
      rows: [
        ["9", "Turnover - business income", gbp(tax.turnover)],
        ["20", "Allowable business expenses, including mileage deduction", gbp(tax.expenses)],
        ["31", "Net profit", gbp(tax.profit)]
      ],
      widths: [0.18, 0.54, 0.28],
      rightAligned: [2]
    )
    drawKeyValue("Income Tax estimate", gbp(tax.incomeTax))
    drawKeyValue("Class 4 NIC estimate", gbp(tax.class4))
    drawKeyValue("Estimated total due", gbp(tax.totalDue), highlighted: true)
    if tax.paymentOnAccount > 0 {
      drawKeyValue("Payment on account", "\(gbp(tax.paymentOnAccount)) each")
    }
    drawKeyValue("Trading allowance", tax.usesTradingAllowance ? "Used" : "Not used")
  }

  private func drawIncome() {
    drawSectionTitle("Income by platform")
    var totals: [String: Double] = [:]
    incomeRecords.forEach { record in
      totals[record.platform ?? "Other", default: 0] += record.amount ?? 0
    }
    let rows = totals
      .sorted { $0.value > $1.value }
      .map { [$0.key, gbp($0.value)] }
    drawTable(
      headers: ["Platform", "Amount"],
      rows: rows,
      widths: [0.66, 0.34],
      rightAligned: [1],
      emptyMessage: "No income records logged for this tax year."
    )
    drawKeyValue("Total turnover", gbp(store.taxPosition.turnover), highlighted: true)
  }

  private func drawMileage() {
    drawSectionTitle("Mileage log")
    let tripRows = yearTrips.map { trip in
      [
        nativeUkDateStamp(trip.startedAt),
        trip.vehicle.label,
        "GPS trip",
        miles(trip.miles),
        gbp(trip.deduction)
      ]
    }
    let manualRows = manualMileageRecords.map { record in
      [
        nativeUkDateStamp(record.date),
        record.vehicle?.label ?? "Vehicle",
        "Manual",
        miles(record.miles ?? 0),
        gbp(record.deduction ?? 0)
      ]
    }
    drawWrapped(
      "Tracked trips with saved route points support a contemporaneous mileage log. Your accountant should review the business purpose and completeness.",
      font: .systemFont(ofSize: 10.5, weight: .regular),
      color: muted,
      spacingAfter: 6
    )
    drawTable(
      headers: ["Date", "Vehicle", "Source", "Miles", "Deduction"],
      rows: tripRows + manualRows,
      widths: [0.20, 0.22, 0.20, 0.16, 0.22],
      rightAligned: [3, 4],
      emptyMessage: "No mileage records logged for this tax year."
    )
    drawKeyValue("Business miles", miles(store.yearMiles), highlighted: true)
    drawKeyValue("Mileage deduction", gbp(store.yearMileageDeduction), highlighted: true)
  }

  private func drawExpenses() {
    drawSectionTitle("Expenses")
    let reviewItems = expenseRecords.filter(nativeNeedsAccountantReview)
    let regularItems = expenseRecords.filter { !nativeNeedsAccountantReview($0) }
    drawExpenseTable(regularItems, emptyMessage: "No expense records logged for this tax year.")
    drawKeyValue("Expense total", gbp(expenseRecords.reduce(0) { $0 + ($1.amount ?? 0) }))

    if !reviewItems.isEmpty {
      drawSectionTitle("Items flagged for review")
      drawWrapped(
        "These look like vehicle running costs. If simplified mileage is used, they may already be covered by the mileage rate.",
        font: .systemFont(ofSize: 10.5, weight: .regular),
        color: muted,
        spacingAfter: 6
      )
      drawExpenseTable(reviewItems)
    }
  }

  private func drawExpenseTable(_ records: [NativeRecord], emptyMessage: String = "None.") {
    let rows = records.map { record in
      [
        nativeUkDateStamp(record.date),
        nativeExpenseDescription(record),
        gbp(record.amount ?? 0),
        record.receiptImageData == nil ? "No" : "Attached"
      ]
    }
    drawTable(
      headers: ["Date", "Description", "Amount", "Receipt"],
      rows: rows,
      widths: [0.20, 0.44, 0.20, 0.16],
      rightAligned: [2],
      emptyMessage: emptyMessage
    )
  }

  private func drawReceipts() {
    let receipts = expenseRecords.compactMap { record -> (NativeRecord, UIImage)? in
      guard let data = record.receiptImageData, let image = UIImage(data: data) else { return nil }
      return (record, image)
    }
    guard !receipts.isEmpty else { return }

    drawSectionTitle("Receipt images")
    for (record, image) in receipts {
      let caption = "\(nativeUkDateStamp(record.date)) - \(nativeExpenseDescription(record)) - \(gbp(record.amount ?? 0))"
      let captionHeight = measuredHeight(caption, font: .systemFont(ofSize: 9.5, weight: .semibold), width: contentWidth)
      let maxImageWidth = contentWidth
      let maxImageHeight: CGFloat = 270
      let scale = min(maxImageWidth / max(image.size.width, 1), maxImageHeight / max(image.size.height, 1), 1)
      let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      ensure(captionHeight + imageSize.height + 20)
      drawWrapped(caption, font: .systemFont(ofSize: 9.5, weight: .semibold), color: muted, spacingAfter: 5)
      let imageRect = CGRect(x: margin, y: y, width: imageSize.width, height: imageSize.height)
      image.draw(in: imageRect)
      line.setStroke()
      UIBezierPath(roundedRect: imageRect, cornerRadius: 5).stroke()
      y += imageSize.height + 16
    }
  }

  private func drawLimitations() {
    drawSectionTitle("Basis and limitations")
    drawWrapped(
      "Prepared by Okkle from records kept on the user's device. Figures are estimates derived from logged data, have not been independently verified or reconciled to bank records, and do not constitute tax advice. Confirm completeness, categorisation and final figures before submission.",
      font: .systemFont(ofSize: 10, weight: .regular),
      color: muted,
      spacingAfter: 0
    )
  }

  private func drawInfoBox(_ rows: [(String, String)]) {
    let rowHeight: CGFloat = 24
    let boxHeight = CGFloat(rows.count) * rowHeight + 18
    ensure(boxHeight)
    let rect = CGRect(x: margin, y: y, width: contentWidth, height: boxHeight)
    pale.setFill()
    UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
    line.setStroke()
    UIBezierPath(roundedRect: rect, cornerRadius: 10).stroke()
    y += 9
    rows.forEach { label, value in
      drawString(label, in: CGRect(x: margin + 12, y: y, width: 150, height: rowHeight), font: .systemFont(ofSize: 10.5, weight: .semibold), color: muted)
      drawString(value, in: CGRect(x: margin + 170, y: y, width: contentWidth - 194, height: rowHeight), font: .systemFont(ofSize: 10.5, weight: .bold), color: ink, alignment: .right)
      y += rowHeight
    }
    y += 13
  }

  private func drawSectionTitle(_ title: String) {
    ensure(42)
    y += y > margin + 2 ? 14 : 0
    drawWrapped(title, font: .systemFont(ofSize: 15, weight: .heavy), color: brand, spacingAfter: 5)
    brand.withAlphaComponent(0.22).setFill()
    UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: 2), cornerRadius: 1).fill()
    y += 9
  }

  private func drawKeyValue(_ label: String, _ value: String, highlighted: Bool = false) {
    let labelWidth = contentWidth * 0.48
    let valueWidth = contentWidth - labelWidth
    let labelFont = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
    let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: highlighted ? .bold : .semibold)
    let height = max(
      measuredHeight(label, font: labelFont, width: labelWidth),
      measuredHeight(value, font: valueFont, width: valueWidth)
    ) + 10
    ensure(height)
    if highlighted {
      pale.setFill()
      UIBezierPath(roundedRect: CGRect(x: margin - 6, y: y - 2, width: contentWidth + 12, height: height), cornerRadius: 6).fill()
    }
    drawString(label, in: CGRect(x: margin, y: y + 4, width: labelWidth, height: height), font: labelFont, color: muted)
    drawString(value, in: CGRect(x: margin + labelWidth, y: y + 4, width: valueWidth, height: height), font: valueFont, color: highlighted ? brand : ink, alignment: .right)
    y += height
    drawHairline()
  }

  private func drawTable(
    headers: [String],
    rows: [[String]],
    widths: [CGFloat],
    rightAligned: Set<Int> = [],
    emptyMessage: String = "None recorded."
  ) {
    let total = widths.reduce(0, +)
    let columnWidths = widths.map { contentWidth * ($0 / total) }
    drawTableRow(headers, widths: columnWidths, rightAligned: rightAligned, font: .systemFont(ofSize: 9.4, weight: .bold), textColor: ink, background: UIColor(red: 0.94, green: 0.94, blue: 0.92, alpha: 1))

    if rows.isEmpty {
      drawTableRow([emptyMessage], widths: [contentWidth], rightAligned: [], font: .systemFont(ofSize: 9.4, weight: .regular), textColor: muted, background: nil)
    } else {
      rows.forEach { row in
        drawTableRow(row, widths: columnWidths, rightAligned: rightAligned, font: .systemFont(ofSize: 9.2, weight: .regular), textColor: ink, background: nil)
      }
    }
    y += 5
  }

  private func drawTableRow(_ values: [String], widths: [CGFloat], rightAligned: Set<Int>, font: UIFont, textColor: UIColor, background: UIColor?) {
    let padding: CGFloat = 6
    let cellHeights = values.enumerated().map { index, value in
      measuredHeight(value, font: font, width: max(1, widths[index] - padding * 2))
    }
    let rowHeight = max(24, (cellHeights.max() ?? 12) + padding * 2)
    ensure(rowHeight)
    if let background {
      background.setFill()
      UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)).fill()
    }

    var x = margin
    for (index, value) in values.enumerated() {
      let width = widths[index]
      let rect = CGRect(x: x + padding, y: y + padding, width: width - padding * 2, height: rowHeight - padding)
      drawString(value, in: rect, font: font, color: textColor, alignment: rightAligned.contains(index) ? .right : .left)
      x += width
    }
    y += rowHeight
    drawHairline()
  }

  private func drawHairline() {
    line.setStroke()
    let path = UIBezierPath()
    path.move(to: CGPoint(x: margin, y: y))
    path.addLine(to: CGPoint(x: margin + contentWidth, y: y))
    path.lineWidth = 0.5
    path.stroke()
  }

  @discardableResult
  private func drawWrapped(_ value: String, font: UIFont, color: UIColor, spacingAfter: CGFloat) -> CGFloat {
    let height = measuredHeight(value, font: font, width: contentWidth)
    ensure(height + spacingAfter)
    drawString(value, in: CGRect(x: margin, y: y, width: contentWidth, height: height), font: font, color: color)
    y += height + spacingAfter
    return height
  }

  private func drawString(_ value: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph
    ]
    (value as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
  }

  private func measuredHeight(_ value: String, font: UIFont, width: CGFloat) -> CGFloat {
    let rect = (value as NSString).boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font],
      context: nil
    )
    return ceil(rect.height)
  }
}

private func nativeExpenseDescription(_ record: NativeRecord) -> String {
  [record.merchant, record.category ?? "Expense"]
    .compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }
    .joined(separator: " - ")
}

private func nativeNeedsAccountantReview(_ record: NativeRecord) -> Bool {
  let text = "\(record.category ?? "") \(record.merchant ?? "")".lowercased()
  let terms = ["fuel", "petrol", "diesel", "tyre", "tire", "mot", "service", "servicing", "repair", "insurance", "road tax", "breakdown", "oil", "brake", "battery"]
  return terms.contains { text.contains($0) }
}

private func nativeLongDate(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_GB")
  formatter.dateStyle = .long
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
