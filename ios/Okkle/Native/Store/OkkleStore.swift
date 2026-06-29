import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
@MainActor
final class OkkleStore: ObservableObject {
  static let shared = OkkleStore()

  private struct TaxYearMileageEntry {
    var date: Date
    var miles: Double
    var vehicle: NativeVehicle
  }

  @Published var settings = NativeSettings() { didSet { save() } }
  @Published var records: [NativeRecord] = [] { didSet { save() } }
  @Published var trips: [NativeTrip] = [] { didSet { save() } }

  private let key = "uk.okkle.native.swiftui.snapshot.v1"
  private let legacyMigrationKey = "uk.okkle.native.swiftui.legacySqliteMigration.v2"
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

    if normalizeOnboardingState() {
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

  @discardableResult
  func restoreBackupData(_ data: Data) throws -> NativeBackupRestoreSummary {
    let snapshot = try decodeBackupSnapshot(from: data)
    isLoading = true
    settings = snapshot.settings
    records = snapshot.records
    trips = snapshot.trips
    _ = normalizeOnboardingState()
    isLoading = false
    save()
    return NativeBackupRestoreSummary(records: records.count, trips: trips.count)
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
    isLoading = true
    settings = NativeSettings()
    records = []
    trips = []
    isLoading = false
    UserDefaults.standard.removeObject(forKey: nativeSeenMedalsKey)
    save()
  }

  func completeOnboarding(name: String, defaultVehicle: NativeVehicle, platforms: [String], region: NativeRegion, incomeBracket: NativeIncomeBracket) {
    var updated = settings
    updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    updated.defaultVehicle = defaultVehicle
    updated.platforms = uniqueStrings(platforms)
    if updated.platforms.isEmpty {
      updated.platforms = ["Uber Eats"]
    }
    updated.region = region
    updated.incomeBracket = incomeBracket
    updated.hasCompletedOnboarding = true
    settings = updated
  }

  var taxYear: DateInterval {
    TaxCalculator.taxYearInterval(containing: Date())
  }

  var yearRecords: [NativeRecord] {
    records.filter { recordOverlapsTaxYear($0) }
  }

  var yearTrips: [NativeTrip] {
    trips.filter { taxYear.contains($0.startedAt) }
  }

  var yearMiles: Double {
    yearMileageEntries.reduce(0) { $0 + $1.miles }
  }

  var yearMileageDeduction: Double {
    var total = 0.0
    var carAndVanMilesBefore = 0.0

    for entry in yearMileageEntries {
      switch entry.vehicle {
      case .car, .van:
        total += calcDeduction(
          miles: entry.miles,
          vehicle: entry.vehicle,
          totalBefore: carAndVanMilesBefore,
          date: entry.date
        )
        carAndVanMilesBefore += entry.miles
      case .motorbike, .bike:
        total += calcDeduction(miles: entry.miles, vehicle: entry.vehicle, date: entry.date)
      }
    }

    return total
  }

  var yearIncome: Double {
    yearRecords.reduce(0) { $0 + incomeForTaxYear($1) }
  }

  var yearExpenses: Double {
    yearRecords.reduce(0) { $0 + expenseForTaxYear($1) } + yearMileageDeduction
  }

  var taxSaved: Double {
    yearMileageDeduction * settings.incomeBracket.marginalRate(region: settings.region)
  }

  var taxPosition: NativeTaxPosition {
    TaxCalculator.estimate(turnover: yearIncome, expenses: yearExpenses, region: settings.region, incomeBracket: settings.incomeBracket)
  }

  var history: [NativeHistoryItem] {
    let tripItems = trips.map(NativeHistoryItem.trip)
    let recordItems = records.map(NativeHistoryItem.record)
    return (tripItems + recordItems).sorted { $0.date > $1.date }
  }

  func periodBounds(for date: Date, period: NativePayPeriod) -> (start: Date, end: Date) {
    TaxCalculator.periodBounds(for: date, period: period)
  }

  func calcDeduction(miles: Double, vehicle: NativeVehicle, totalBefore: Double = 0, date: Date = Date()) -> Double {
    TaxCalculator.mileageDeduction(miles: miles, vehicle: vehicle, totalBefore: totalBefore, date: date)
  }

  private func decodeBackupSnapshot(from data: Data) throws -> NativeSnapshot {
    let isoDecoder = JSONDecoder()
    isoDecoder.dateDecodingStrategy = .iso8601
    if let payload = try? isoDecoder.decode(NativeBackupPayload.self, from: data),
       payload.app.caseInsensitiveCompare("okkle") == .orderedSame {
      return payload.snapshot
    }
    if let snapshot = try? isoDecoder.decode(NativeSnapshot.self, from: data) {
      return snapshot
    }

    let decoder = JSONDecoder()
    if let payload = try? decoder.decode(NativeBackupPayload.self, from: data),
       payload.app.caseInsensitiveCompare("okkle") == .orderedSame {
      return payload.snapshot
    }
    if let snapshot = try? decoder.decode(NativeSnapshot.self, from: data) {
      return snapshot
    }

    throw NativeBackupRestoreError.invalidBackup
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

  private func normalizeOnboardingState() -> Bool {
    guard !settings.hasCompletedOnboarding else { return false }
    let hasProfileName = !settings.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    guard hasProfileName || !records.isEmpty || !trips.isEmpty else { return false }
    settings.hasCompletedOnboarding = true
    return true
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

  private var yearMileageEntries: [TaxYearMileageEntry] {
    let tripEntries = yearTrips.compactMap { trip -> TaxYearMileageEntry? in
      let miles = max(0, trip.miles)
      guard miles > 0 else { return nil }
      return TaxYearMileageEntry(date: trip.startedAt, miles: miles, vehicle: trip.vehicle)
    }

    let recordEntries = yearRecords.compactMap { record -> TaxYearMileageEntry? in
      guard record.kind == .mileage else { return nil }
      let miles = max(0, record.miles ?? 0) * taxYearShare(for: record)
      guard miles > 0 else { return nil }
      return TaxYearMileageEntry(
        date: record.date,
        miles: miles,
        vehicle: record.vehicle ?? settings.defaultVehicle
      )
    }

    return (tripEntries + recordEntries).sorted { lhs, rhs in
      if lhs.date == rhs.date {
        return lhs.vehicle.rawValue < rhs.vehicle.rawValue
      }
      return lhs.date < rhs.date
    }
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
