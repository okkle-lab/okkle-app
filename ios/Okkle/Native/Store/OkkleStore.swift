import Combine
import Foundation
import UIKit
@MainActor
final class OkkleStore: ObservableObject {
  static let shared = OkkleStore()

  private struct TaxYearMileageEntry {
    var date: Date
    var miles: Double
    var vehicle: NativeVehicle
    var source: String = "GPS"
    var interval: DateInterval? = nil
    var fromAddress: String? = nil
    var toAddress: String? = nil
  }

  @Published var settings = NativeSettings() { didSet { scheduleSave() } }
  @Published var records: [NativeRecord] = [] { didSet { cachedHistory = nil; scheduleSave() } }
  @Published var trips: [NativeTrip] = [] { didSet { cachedHistory = nil; scheduleSave() } }
  @Published private(set) var iCloudSyncState: NativeICloudSyncState = .disabled

  private let key = "uk.okkle.native.swiftui.snapshot.v1"
  private let legacyMigrationKey = "uk.okkle.native.swiftui.legacySqliteMigration.v3"
  private let saveDebounceInterval: TimeInterval = 0.45
  private var isLoading = false
  private var pendingSave: DispatchWorkItem?
  private var cachedHistory: [NativeHistoryItem]?
  private var isApplyingICloudSnapshot = false
  // The legacy SQLite mirror only exists so an older build can recover the
  // data; rebuilding it on every save is wasted work, so it's deferred to
  // the next trip into the background.
  private var legacyExportNeeded = false
  private let persistenceQueue = DispatchQueue(label: "uk.okkle.native.snapshot-persist", qos: .utility)

  private static let snapshotFileURL: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Okkle", isDirectory: true).appendingPathComponent("snapshot.json")
  }()

  init() {
    load()
    scheduleLegacyImport()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
  }

  func load() {
    isLoading = true
    var shouldPersist = false
    defer {
      isLoading = false
      if shouldPersist { save() }
    }

    // Snapshots moved from UserDefaults to a file in Application Support;
    // the defaults read is the migration path, cleaned up on the next save.
    if let data = (try? Data(contentsOf: Self.snapshotFileURL)) ?? UserDefaults.standard.data(forKey: key) {
      do {
        let snapshot = try JSONDecoder().decode(NativeSnapshot.self, from: data)
        settings = snapshot.settings
        records = snapshot.records
        trips = snapshot.trips
      } catch {
        try? FileManager.default.removeItem(at: Self.snapshotFileURL)
        UserDefaults.standard.removeObject(forKey: key)
      }
    }

    if normalizeOnboardingState() {
      shouldPersist = true
    }

    iCloudSyncState = settings.iCloudSyncEnabled ? .syncing : .disabled
  }

  @objc private func appDidEnterBackground() {
    if pendingSave != nil { save() }
    refreshICloudSyncIfNeeded()
    guard legacyExportNeeded else { return }
    legacyExportNeeded = false
    let snapshot = NativeSnapshot(settings: settings, records: records, trips: trips)
    persistenceQueue.async {
      NativeLegacySQLiteExporter.write(snapshot: snapshot)
    }
  }

  private func scheduleLegacyImport() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let imported = NativeLegacySQLiteImporter.importSnapshot() else { return }
      DispatchQueue.main.async {
        self?.applyLegacyImport(imported)
      }
    }
  }

  private func applyLegacyImport(_ imported: NativeLegacyImportResult) {
    isLoading = true
    merge(imported)
    _ = normalizeOnboardingState()
    isLoading = false
    UserDefaults.standard.set(true, forKey: legacyMigrationKey)
    save()
  }

  func save(uploadToICloud: Bool = true) {
    guard !isLoading else { return }
    pendingSave?.cancel()
    pendingSave = nil
    persistSnapshot(uploadToICloud: uploadToICloud)
  }

  private func scheduleSave() {
    guard !isLoading else { return }
    pendingSave?.cancel()

    let work = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        self?.pendingSave = nil
        self?.persistSnapshot()
      }
    }
    pendingSave = work
    DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: work)
  }

  private func persistSnapshot(uploadToICloud: Bool = true) {
    let snapshot = NativeSnapshot(settings: settings, records: records, trips: trips)
    legacyExportNeeded = true
    let url = Self.snapshotFileURL
    let defaultsKey = key
    persistenceQueue.async {
      guard let data = try? JSONEncoder().encode(snapshot) else { return }
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      do {
        try data.write(to: url, options: .atomic)
        // Only drop the old UserDefaults copy once the file write succeeded,
        // so a migration interrupted mid-flight loses nothing.
        UserDefaults.standard.removeObject(forKey: defaultsKey)
      } catch {}
    }
    if uploadToICloud, snapshot.settings.iCloudSyncEnabled, !isApplyingICloudSnapshot {
      NativeICloudSyncEngine.shared.uploadLocalSnapshot(snapshot, store: self)
    }
  }

  var currentSnapshot: NativeSnapshot {
    NativeSnapshot(settings: settings, records: records, trips: trips)
  }

  var isFreshInstallForICloudOffer: Bool {
    !settings.hasCompletedOnboarding &&
      settings.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      records.isEmpty &&
      trips.isEmpty
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
    guard !settings.iCloudSyncEnabled else {
      throw NativeBackupRestoreError.iCloudSyncEnabled
    }
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

  func setICloudSyncEnabled(_ isEnabled: Bool) {
    guard settings.iCloudSyncEnabled != isEnabled else {
      refreshICloudSyncIfNeeded()
      return
    }
    if isEnabled {
      isLoading = true
      settings.iCloudSyncEnabled = true
      isLoading = false
      save(uploadToICloud: false)
      NativeICloudSyncEngine.shared.refresh(store: self, mergeCloudData: true)
    } else {
      settings.iCloudSyncEnabled = false
      iCloudSyncState = .disabled
    }
  }

  func refreshICloudSyncIfNeeded() {
    NativeICloudSyncEngine.shared.refresh(store: self)
  }

  func existingICloudDataCheck() async -> NativeICloudRemoteSnapshotCheck {
    await NativeICloudSyncEngine.shared.remoteSnapshotSummary()
  }

  func restoreExistingICloudData() async throws {
    try await NativeICloudSyncEngine.shared.restoreExistingRemoteData(store: self)
  }

  func setICloudSyncState(_ state: NativeICloudSyncState) {
    iCloudSyncState = state
  }

  func applyICloudSnapshot(_ snapshot: NativeSnapshot) {
    isApplyingICloudSnapshot = true
    isLoading = true
    settings = snapshot.settings
    records = snapshot.records
    trips = snapshot.trips
    _ = normalizeOnboardingState()
    isLoading = false
    save(uploadToICloud: false)
    isApplyingICloudSnapshot = false
  }

  /// Set by the passive-insights layer so it can quietly check its own
  /// predictions against newly logged pay, without this store needing to know
  /// anything about Insights' domain types.
  var onRecordAdded: ((NativeRecord) -> Void)?

  func addRecord(_ record: NativeRecord) {
    records.insert(record, at: 0)
    onRecordAdded?(record)
    refreshLogSensitiveNotifications()
  }

  func addTrip(_ trip: NativeTrip) {
    trips.insert(trip, at: 0)
    refreshLogSensitiveNotifications()
    NativeTripAddressResolver.resolveAddresses(for: trip.id, store: self)
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

  private func refreshLogSensitiveNotifications() {
    NativeLoggingReminder.refresh(store: self)
    NativePreShiftNotifier.refresh(store: self)
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

  /// The mileage log, one row per entry, for the current tax year — each
  /// row's deduction computed against the *same* running car/van total
  /// yearMileageDeduction itself accumulates, so the two always agree once
  /// summed. A trip or manual record's own stored `deduction` field is set
  /// at logging time against a running total of zero (it can't know what
  /// else that tax year will hold yet), so it's only ever right for whoever
  /// stays under the 10,000-mile HMRC simplified-rate threshold for the
  /// whole year — anyone who crosses it needs every later entry recomputed
  /// at the lower after-threshold rate, which is what this does.
  var yearMileageLogRows: [NativeMileageLogRow] {
    var rows: [NativeMileageLogRow] = []
    var carAndVanMilesBefore = 0.0

    for entry in yearMileageEntries {
      let deduction: Double
      switch entry.vehicle {
      case .car, .van:
        deduction = calcDeduction(
          miles: entry.miles,
          vehicle: entry.vehicle,
          totalBefore: carAndVanMilesBefore,
          date: entry.date
        )
        carAndVanMilesBefore += entry.miles
      case .motorbike, .bike:
        deduction = calcDeduction(miles: entry.miles, vehicle: entry.vehicle, date: entry.date)
      }
      rows.append(NativeMileageLogRow(
        date: entry.date,
        vehicle: entry.vehicle,
        source: entry.source,
        miles: entry.miles,
        deduction: deduction,
        fromAddress: entry.fromAddress,
        toAddress: entry.toAddress
      ))
    }

    return rows
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

  func mileageTaxSavings(for interval: DateInterval?) -> NativeMileageTaxSavings {
    var miles = 0.0
    var mileageDeduction = 0.0
    var carAndVanMilesByTaxYear: [Date: Double] = [:]

    for entry in allMileageEntries {
      let selectedMiles = selectedMiles(for: entry, within: interval)
      let taxYearStart = TaxCalculator.taxYearInterval(containing: entry.date).start

      switch entry.vehicle {
      case .car, .van:
        let totalBefore = carAndVanMilesByTaxYear[taxYearStart] ?? 0
        if selectedMiles > 0 {
          miles += selectedMiles
          mileageDeduction += calcDeduction(
            miles: selectedMiles,
            vehicle: entry.vehicle,
            totalBefore: totalBefore,
            date: entry.date
          )
        }
        carAndVanMilesByTaxYear[taxYearStart] = totalBefore + entry.miles
      case .motorbike, .bike:
        if selectedMiles > 0 {
          miles += selectedMiles
          mileageDeduction += calcDeduction(miles: selectedMiles, vehicle: entry.vehicle, date: entry.date)
        }
      }
    }

    return NativeMileageTaxSavings(
      miles: miles,
      mileageDeduction: mileageDeduction,
      taxSaved: mileageDeduction * settings.incomeBracket.marginalRate(region: settings.region)
    )
  }

  var taxPosition: NativeTaxPosition {
    TaxCalculator.estimate(
      turnover: yearIncome,
      expenses: yearExpenses,
      region: settings.region,
      incomeBracket: settings.incomeBracket,
      otherIncome: settings.otherIncome
    )
  }

  var history: [NativeHistoryItem] {
    if let cachedHistory { return cachedHistory }
    let tripItems = trips.map(NativeHistoryItem.trip)
    let recordItems = records.map(NativeHistoryItem.record)
    let items = (tripItems + recordItems).sorted { $0.date > $1.date }
    cachedHistory = items
    return items
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

    if let legacySnapshot = NativeLegacyBackupImporter.snapshot(from: data) {
      return legacySnapshot
    }

    throw NativeBackupRestoreError.invalidBackup
  }

  private func merge(_ imported: NativeLegacyImportResult) {
    if let importedSettings = imported.settings {
      mergeSettings(importedSettings)
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

  private func mergeSettings(_ importedSettings: NativeSettings) {
    let currentLooksEmpty = settings == NativeSettings() ||
      (!settings.hasCompletedOnboarding &&
       settings.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
       records.isEmpty &&
       trips.isEmpty)

    guard !currentLooksEmpty else {
      settings = importedSettings
      return
    }

    var updated = settings
    if updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      updated.name = importedSettings.name
    }
    if updated.platforms == NativeSettings().platforms, importedSettings.platforms != NativeSettings().platforms {
      updated.platforms = importedSettings.platforms
    }
    if updated.accountantUTR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      updated.accountantUTR = importedSettings.accountantUTR
    }
    if updated.accountantNINumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      updated.accountantNINumber = importedSettings.accountantNINumber
    }
    if updated.accountantAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      updated.accountantAddress = importedSettings.accountantAddress
    }
    if updated.accountantBusinessDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      updated.accountantBusinessDescription = importedSettings.accountantBusinessDescription
    }
    settings = updated
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
      return TaxYearMileageEntry(
        date: trip.startedAt,
        miles: miles,
        vehicle: trip.vehicle,
        fromAddress: trip.startAddress,
        toAddress: trip.endAddress
      )
    }

    let recordEntries = yearRecords.compactMap { record -> TaxYearMileageEntry? in
      guard record.kind == .mileage else { return nil }
      let miles = max(0, record.miles ?? 0) * taxYearShare(for: record)
      guard miles > 0 else { return nil }
      return TaxYearMileageEntry(
        date: record.date,
        miles: miles,
        vehicle: record.vehicle ?? settings.defaultVehicle,
        source: "Manual"
      )
    }

    return (tripEntries + recordEntries).sorted { lhs, rhs in
      if lhs.date == rhs.date {
        return lhs.vehicle.rawValue < rhs.vehicle.rawValue
      }
      return lhs.date < rhs.date
    }
  }

  private var allMileageEntries: [TaxYearMileageEntry] {
    let tripEntries = trips.compactMap { trip -> TaxYearMileageEntry? in
      let miles = max(0, trip.miles)
      guard miles > 0 else { return nil }
      return TaxYearMileageEntry(date: trip.startedAt, miles: miles, vehicle: trip.vehicle)
    }

    let recordEntries = records.compactMap { record -> TaxYearMileageEntry? in
      guard record.kind == .mileage else { return nil }
      let miles = max(0, record.miles ?? 0)
      guard miles > 0 else { return nil }
      return TaxYearMileageEntry(
        date: record.date,
        miles: miles,
        vehicle: record.vehicle ?? settings.defaultVehicle,
        interval: recordInterval(record)
      )
    }

    return (tripEntries + recordEntries).sorted { lhs, rhs in
      if lhs.date == rhs.date {
        return lhs.vehicle.rawValue < rhs.vehicle.rawValue
      }
      return lhs.date < rhs.date
    }
  }

  private func selectedMiles(for entry: TaxYearMileageEntry, within interval: DateInterval?) -> Double {
    guard let interval else { return entry.miles }

    if let entryInterval = entry.interval {
      guard entryInterval.duration > 0, let overlap = entryInterval.intersection(with: interval) else {
        return 0
      }
      return entry.miles * min(1, max(0, overlap.duration / entryInterval.duration))
    }

    return interval.contains(entry.date) ? entry.miles : 0
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
