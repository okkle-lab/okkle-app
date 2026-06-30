import CoreLocation
import EventKit
import MapKit
import PhotosUI
import SQLite3
import SwiftUI
import UIKit
import Vision
private let nativeSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct NativeLegacyImportResult {
  var settings: NativeSettings?
  var records: [NativeRecord]
  var trips: [NativeTrip]
}

enum NativeLegacySQLiteImporter {
  static func importSnapshot() -> NativeLegacyImportResult? {
    var combined = NativeLegacyImportResult(settings: nil, records: [], trips: [])
    var didFindData = false

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
      let records = readRecords(from: db) + readTripEarningsRecords(from: db)
      if settings != nil || !trips.isEmpty || !records.isEmpty {
        didFindData = true
        if combined.settings == nil {
          combined.settings = settings
        }
        combined.trips.append(contentsOf: trips)
        combined.records.append(contentsOf: records)
      }
    }

    guard didFindData else { return nil }
    combined.trips = uniqueTrips(combined.trips)
    combined.records = uniqueRecords(combined.records)
    return combined
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
      for databaseName in ["okkle.db", "okkle.sqlite", "okkle.sqlite3"] {
        urls.append(root.appendingPathComponent(databaseName))
        urls.append(root.appendingPathComponent("SQLite", isDirectory: true).appendingPathComponent(databaseName))
      }
      if let enumerator = manager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) {
        for case let url as URL in enumerator where looksLikeLegacyDatabase(url) {
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

  private static func looksLikeLegacyDatabase(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    let ext = url.pathExtension.lowercased()
    let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
    guard ["db", "sqlite", "sqlite3"].contains(ext) || name == "okkle.db" else { return false }
    return name.hasPrefix("okkle.") || parent == "sqlite"
  }

  private static func uniqueTrips(_ trips: [NativeTrip]) -> [NativeTrip] {
    var seen = Set<String>()
    return trips.filter { trip in
      let key = trip.legacyID ?? "\(trip.vehicle.rawValue)-\(trip.startedAt.timeIntervalSince1970)-\(trip.miles)"
      guard !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
  }

  private static func uniqueRecords(_ records: [NativeRecord]) -> [NativeRecord] {
    var seen = Set<String>()
    return records.filter { record in
      let key = record.legacyID ?? "\(record.kind.rawValue)-\(record.date.timeIntervalSince1970)-\(record.amount ?? 0)-\(record.miles ?? 0)"
      guard !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
  }

  private static func readSettings(from db: OpaquePointer) -> NativeSettings? {
    let keyValues = readKeyValues(from: db)
    guard let row = rows(from: db, sql: "SELECT * FROM user LIMIT 1").first else {
      guard !keyValues.isEmpty else { return nil }
      var settings = NativeSettings()
      applyAccountantDetails(keyValues, to: &settings)
      applyIncomeBracket(taxRate: legacyTaxRate(from: keyValues), to: &settings)
      settings.otherIncome = legacyOtherIncome(from: keyValues) ?? 0
      return settings
    }
    var settings = NativeSettings()
    settings.name = string(row["name"]) ?? ""
    settings.defaultVehicle = vehicle(from: string(row["vehicle"])) ?? .car
    settings.region = NativeRegion(rawValue: string(row["region"]) ?? "") ?? .ruk
    applyIncomeBracket(taxRate: double(row["tax_rate"]) ?? legacyTaxRate(from: keyValues), to: &settings)
    settings.otherIncome = legacyOtherIncome(from: keyValues) ?? 0
    settings.hasCompletedOnboarding = (int(row["onboarded"]) ?? 1) != 0

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
    applyAccountantDetails(keyValues, to: &settings)

    return settings
  }

  private static func readKeyValues(from db: OpaquePointer) -> [String: String] {
    rows(from: db, sql: "SELECT key, value FROM kv").reduce(into: [:]) { result, row in
      guard let key = nonEmpty(string(row["key"])),
            let value = string(row["value"]) else { return }
      result[key] = value
    }
  }

  private static func applyAccountantDetails(_ values: [String: String], to settings: inout NativeSettings) {
    settings.accountantUTR = nonEmpty(values["utr"]) ?? ""
    settings.accountantNINumber = nonEmpty(values["ni_number"]) ?? ""
    settings.accountantAddress = nonEmpty(values["address"]) ?? ""
    settings.accountantBusinessDescription = nonEmpty(values["business_desc"]) ?? ""
  }

  private static func applyIncomeBracket(taxRate: Double?, to settings: inout NativeSettings) {
    guard let taxRate else { return }
    settings.incomeBracket = taxRate >= 0.40 ? .higher : .basic
  }

  private static func legacyTaxRate(from values: [String: String]) -> Double? {
    values["tax_rate"].flatMap { Double($0) }
  }

  private static func legacyOtherIncome(from values: [String: String]) -> Double? {
    values["other_income"].flatMap { Double($0) }
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

  private static func readTripEarningsRecords(from db: OpaquePointer) -> [NativeRecord] {
    rows(from: db, sql: "SELECT id, platform, earnings, started_at FROM trips WHERE earnings IS NOT NULL AND earnings > 0").compactMap { row in
      guard let id = int(row["id"]),
            let amount = double(row["earnings"]),
            amount > 0 else {
        return nil
      }

      let date = date(row["started_at"]) ?? Date()
      let day = Calendar.current.startOfDay(for: date)
      return NativeRecord(
        legacyID: "sqlite-trip-earnings-\(id)",
        kind: .income,
        platform: nonEmpty(string(row["platform"])),
        vehicle: nil,
        amount: amount,
        miles: nil,
        deduction: nil,
        category: nil,
        merchant: nil,
        date: date,
        period: .day,
        periodStart: day,
        periodEnd: day,
        receiptImageData: nil
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

enum NativeLegacySQLiteExporter {
  static func write(snapshot: NativeSnapshot) {
    guard let url = databaseURL() else { return }
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
          let db else {
      sqlite3_close(db)
      return
    }
    defer { sqlite3_close(db) }

    guard prepareSchema(in: db) else { return }
    guard exec("BEGIN IMMEDIATE TRANSACTION", in: db) else { return }

    guard exec("DELETE FROM trips; DELETE FROM records; DELETE FROM user; DELETE FROM kv;", in: db),
          insertUser(snapshot.settings, hasContent: !snapshot.records.isEmpty || !snapshot.trips.isEmpty, into: db),
          insertTrips(snapshot.trips, into: db),
          insertRecords(snapshot.records, into: db),
          insertKeyValues(from: snapshot.settings, into: db) else {
      _ = exec("ROLLBACK", in: db)
      return
    }

    _ = exec("COMMIT", in: db)
  }

  private static func databaseURL() -> URL? {
    let manager = FileManager.default
    let roots = [
      manager.urls(for: .documentDirectory, in: .userDomainMask).first,
      manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
      manager.urls(for: .libraryDirectory, in: .userDomainMask).first,
    ].compactMap { $0 }

    var candidates: [URL] = []
    for root in roots {
      for databaseName in ["okkle.db", "okkle.sqlite", "okkle.sqlite3"] {
        candidates.append(root.appendingPathComponent("SQLite", isDirectory: true).appendingPathComponent(databaseName))
        candidates.append(root.appendingPathComponent(databaseName))
      }
    }

    if let existing = candidates.first(where: { manager.fileExists(atPath: $0.path) }) {
      return existing
    }

    return manager.urls(for: .documentDirectory, in: .userDomainMask).first?
      .appendingPathComponent("SQLite", isDirectory: true)
      .appendingPathComponent("okkle.db")
  }

  private static func prepareSchema(in db: OpaquePointer) -> Bool {
    let schema = """
      CREATE TABLE IF NOT EXISTS user (
        id INTEGER PRIMARY KEY,
        name TEXT,
        vehicle TEXT DEFAULT 'car',
        vehicles TEXT,
        tax_rate REAL DEFAULT 0.20,
        region TEXT DEFAULT 'ruk',
        platforms TEXT DEFAULT 'Uber Eats',
        reminder_enabled INTEGER DEFAULT 1,
        reminder_day TEXT DEFAULT 'sun',
        log_frequency TEXT DEFAULT 'weekly',
        onboarded INTEGER DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        platform TEXT NOT NULL,
        vehicle TEXT NOT NULL,
        miles REAL NOT NULL,
        deduction REAL NOT NULL,
        earnings REAL,
        started_at TEXT NOT NULL,
        ended_at TEXT NOT NULL,
        route_json TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      );

      CREATE TABLE IF NOT EXISTS kv (
        key TEXT PRIMARY KEY,
        value TEXT
      );

      CREATE TABLE IF NOT EXISTS records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_type TEXT NOT NULL,
        platform TEXT,
        amount REAL,
        miles REAL,
        deduction REAL,
        category TEXT,
        period_start TEXT,
        period_end TEXT,
        receipt_uri TEXT,
        notes TEXT,
        vehicle TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      );
      """

    guard exec(schema, in: db) else { return false }

    for migration in [
      "ALTER TABLE user ADD COLUMN region TEXT DEFAULT 'ruk'",
      "ALTER TABLE user ADD COLUMN reminder_enabled INTEGER DEFAULT 1",
      "ALTER TABLE user ADD COLUMN reminder_day TEXT DEFAULT 'sun'",
      "ALTER TABLE user ADD COLUMN log_frequency TEXT DEFAULT 'weekly'",
      "ALTER TABLE trips ADD COLUMN zone TEXT",
      "ALTER TABLE user ADD COLUMN vehicles TEXT",
      "ALTER TABLE records ADD COLUMN vehicle TEXT",
    ] {
      _ = exec(migration, in: db)
    }
    return true
  }

  private static func insertUser(_ settings: NativeSettings, hasContent: Bool, into db: OpaquePointer) -> Bool {
    let hasProfile = settings.hasCompletedOnboarding ||
      hasContent ||
      !settings.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    guard hasProfile else { return true }

    return withStatement(
      """
      INSERT INTO user (name, vehicle, vehicles, tax_rate, region, platforms,
        reminder_enabled, reminder_day, log_frequency, onboarded)
      VALUES (?,?,?,?,?,?,?,?,?,?)
      """,
      in: db
    ) { statement in
      bindText(settings.name, at: 1, in: statement)
      bindText(settings.defaultVehicle.rawValue, at: 2, in: statement)
      bindText(settings.defaultVehicle.rawValue, at: 3, in: statement)
      sqlite3_bind_double(statement, 4, settings.incomeBracket.marginalRate(region: settings.region))
      bindText(settings.region.rawValue, at: 5, in: statement)
      bindText(settings.platforms.joined(separator: ","), at: 6, in: statement)
      sqlite3_bind_int(statement, 7, settings.loggingReminder ? 1 : 0)
      bindText(weekdayCode(settings.reminderDay), at: 8, in: statement)
      bindText(settings.logFrequency.rawValue, at: 9, in: statement)
      sqlite3_bind_int(statement, 10, settings.hasCompletedOnboarding ? 1 : 0)
      return sqlite3_step(statement) == SQLITE_DONE
    }
  }

  private static func insertTrips(_ trips: [NativeTrip], into db: OpaquePointer) -> Bool {
    for trip in trips.sorted(by: { $0.startedAt < $1.startedAt }) {
      let ok = withStatement(
        """
        INSERT INTO trips (platform, vehicle, miles, deduction, earnings, started_at, ended_at, route_json, created_at)
        VALUES (?,?,?,?,?,?,?,?,?)
        """,
        in: db
      ) { statement in
        bindText("", at: 1, in: statement)
        bindText(trip.vehicle.rawValue, at: 2, in: statement)
        sqlite3_bind_double(statement, 3, trip.miles)
        sqlite3_bind_double(statement, 4, trip.deduction)
        sqlite3_bind_null(statement, 5)
        bindText(legacyDateTime(trip.startedAt), at: 6, in: statement)
        bindText(legacyDateTime(trip.endedAt), at: 7, in: statement)
        bindNullableText(routeJSON(trip.points), at: 8, in: statement)
        bindText(legacyDateTime(trip.startedAt), at: 9, in: statement)
        return sqlite3_step(statement) == SQLITE_DONE
      }
      guard ok else { return false }
    }
    return true
  }

  private static func insertRecords(_ records: [NativeRecord], into db: OpaquePointer) -> Bool {
    for record in records.sorted(by: { $0.date < $1.date }) {
      let ok = withStatement(
        """
        INSERT INTO records (record_type, platform, amount, miles, deduction, category,
          period_start, period_end, receipt_uri, notes, vehicle, created_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
        """,
        in: db
      ) { statement in
        bindText(record.kind.rawValue, at: 1, in: statement)
        bindNullableText(record.platform, at: 2, in: statement)
        bindNullableDouble(record.amount, at: 3, in: statement)
        bindNullableDouble(record.miles, at: 4, in: statement)
        bindNullableDouble(record.deduction, at: 5, in: statement)
        bindNullableText(record.category, at: 6, in: statement)
        bindNullableText(record.periodStart.map(legacyDateOnly), at: 7, in: statement)
        bindNullableText(record.periodEnd.map(legacyDateOnly), at: 8, in: statement)
        bindNullableText(receiptURI(for: record), at: 9, in: statement)
        bindNullableText(record.merchant ?? record.category, at: 10, in: statement)
        bindNullableText(record.vehicle?.rawValue, at: 11, in: statement)
        bindText(legacyDateTime(record.date), at: 12, in: statement)
        return sqlite3_step(statement) == SQLITE_DONE
      }
      guard ok else { return false }
    }
    return true
  }

  private static func insertKeyValues(from settings: NativeSettings, into db: OpaquePointer) -> Bool {
    let values: [(String, String)] = [
      ("tax_rate", String(settings.incomeBracket.marginalRate(region: settings.region))),
      ("other_income", String(settings.otherIncome)),
      ("utr", settings.accountantUTR),
      ("ni_number", settings.accountantNINumber),
      ("address", settings.accountantAddress),
      ("business_desc", settings.accountantBusinessDescription),
    ]

    for (key, value) in values {
      let ok = withStatement("INSERT OR REPLACE INTO kv (key, value) VALUES (?,?)", in: db) { statement in
        bindText(key, at: 1, in: statement)
        bindText(value, at: 2, in: statement)
        return sqlite3_step(statement) == SQLITE_DONE
      }
      guard ok else { return false }
    }
    return true
  }

  private static func receiptURI(for record: NativeRecord) -> String? {
    guard let data = record.receiptImageData else { return nil }
    guard let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    let directory = documentURL.appendingPathComponent("OkkleLegacyReceipts", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(record.id.uuidString).jpg")
    try? data.write(to: url, options: [.atomic])
    return url.absoluteString
  }

  private static func routeJSON(_ points: [RoutePoint]) -> String? {
    guard !points.isEmpty else { return nil }
    let values = points.map { point in
      ["lat": point.latitude, "lng": point.longitude]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: values),
          let string = String(data: data, encoding: .utf8) else {
      return nil
    }
    return string
  }

  private static func exec(_ sql: String, in db: OpaquePointer) -> Bool {
    sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
  }

  private static func withStatement(_ sql: String, in db: OpaquePointer, run: (OpaquePointer) -> Bool) -> Bool {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else {
      sqlite3_finalize(statement)
      return false
    }
    defer { sqlite3_finalize(statement) }
    return run(statement)
  }

  private static func bindText(_ value: String, at index: Int32, in statement: OpaquePointer) {
    sqlite3_bind_text(statement, index, value, -1, nativeSQLiteTransient)
  }

  private static func bindNullableText(_ value: String?, at index: Int32, in statement: OpaquePointer) {
    if let value {
      bindText(value, at: index, in: statement)
    } else {
      sqlite3_bind_null(statement, index)
    }
  }

  private static func bindNullableDouble(_ value: Double?, at index: Int32, in statement: OpaquePointer) {
    if let value {
      sqlite3_bind_double(statement, index, value)
    } else {
      sqlite3_bind_null(statement, index)
    }
  }

  private static func weekdayCode(_ index: Int) -> String {
    let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    guard names.indices.contains(index) else { return "mon" }
    return names[index]
  }

  private static func legacyDateTime(_ date: Date) -> String {
    legacyDateTimeFormatter.string(from: date)
  }

  private static func legacyDateOnly(_ date: Date) -> String {
    legacyDateOnlyFormatter.string(from: date)
  }

  private static let legacyDateTimeFormatter: DateFormatter = {
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

enum NativeLegacyBackupImporter {
  static func snapshot(from data: Data) -> NativeSnapshot? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          string(root["app"])?.caseInsensitiveCompare("okkle") == .orderedSame,
          let tripRows = root["trips"] as? [[String: Any]],
          let recordRows = root["records"] as? [[String: Any]] else {
      return nil
    }

    let keyValues = legacyKeyValues(from: root["kv"] as? [[String: Any]] ?? [])
    let settings = settings(
      from: root["user"] as? [String: Any],
      keyValues: keyValues,
      hasContent: !tripRows.isEmpty || !recordRows.isEmpty
    )
    let trips = tripRows.enumerated().compactMap { index, row in
      trip(from: row, index: index)
    }
    let records = recordRows.enumerated().compactMap { index, row in
      record(from: row, index: index)
    } + tripRows.enumerated().compactMap { index, row in
      tripEarningsRecord(from: row, index: index)
    }

    return NativeSnapshot(settings: settings, records: uniqueRecords(records), trips: uniqueTrips(trips))
  }

  private static func settings(from user: [String: Any]?, keyValues: [String: String], hasContent: Bool) -> NativeSettings {
    var settings = NativeSettings()
    if let user {
      settings.name = string(user["name"]) ?? ""
      settings.defaultVehicle = vehicle(from: string(user["vehicle"])) ?? .car
      settings.region = NativeRegion(rawValue: string(user["region"]) ?? "") ?? .ruk
      applyIncomeBracket(taxRate: double(user["tax_rate"]) ?? legacyTaxRate(from: keyValues), to: &settings)
      settings.otherIncome = legacyOtherIncome(from: keyValues) ?? 0

      let platforms = splitList(string(user["platforms"]))
      if !platforms.isEmpty {
        settings.platforms = platforms
      }

      if let enabled = int(user["reminder_enabled"]) {
        settings.loggingReminder = enabled != 0
      }
      if let reminderDay = string(user["reminder_day"]) {
        settings.reminderDay = weekdayIndex(from: reminderDay)
      }
      if let frequency = NativeLogFrequency(rawValue: string(user["log_frequency"]) ?? "") {
        settings.logFrequency = frequency
      }
      settings.hasCompletedOnboarding = (int(user["onboarded"]) ?? 0) != 0 ||
        !settings.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        hasContent
    } else {
      applyIncomeBracket(taxRate: legacyTaxRate(from: keyValues), to: &settings)
      settings.otherIncome = legacyOtherIncome(from: keyValues) ?? 0
      settings.hasCompletedOnboarding = hasContent
    }

    applyAccountantDetails(keyValues, to: &settings)
    return settings
  }

  private static func trip(from row: [String: Any], index: Int) -> NativeTrip? {
    guard let startedAt = date(row["started_at"]) else { return nil }

    let id = int(row["id"]) ?? index
    let tripVehicle = vehicle(from: string(row["vehicle"])) ?? .car
    let miles = double(row["miles"]) ?? 0
    let storedDeduction = double(row["deduction"]) ?? 0
    return NativeTrip(
      legacyID: "json-trip-\(id)",
      vehicle: tripVehicle,
      miles: miles,
      deduction: storedDeduction > 0 ? storedDeduction : calculatedDeduction(miles: miles, vehicle: tripVehicle, date: startedAt),
      startedAt: startedAt,
      endedAt: date(row["ended_at"]) ?? startedAt,
      points: routePoints(from: string(row["route_json"]))
    )
  }

  private static func record(from row: [String: Any], index: Int) -> NativeRecord? {
    guard let kind = NativeLogKind(rawValue: string(row["record_type"]) ?? "") else {
      return nil
    }

    let id = int(row["id"]) ?? index
    let createdAt = date(row["created_at"]) ?? date(row["period_start"]) ?? Date()
    let periodStart = dateOnly(row["period_start"])
    let periodEnd = dateOnly(row["period_end"])
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
      legacyID: "json-record-\(id)",
      kind: kind,
      platform: nonEmpty(string(row["platform"])),
      vehicle: recordVehicle,
      amount: double(row["amount"]),
      miles: miles,
      deduction: deduction,
      category: nonEmpty(string(row["category"]) ?? string(row["notes"])),
      merchant: nil,
      date: createdAt,
      period: periodKind(start: periodStart, end: periodEnd),
      periodStart: periodStart,
      periodEnd: periodEnd,
      receiptImageData: receiptData(from: string(row["receipt_uri"]))
    )
  }

  private static func tripEarningsRecord(from row: [String: Any], index: Int) -> NativeRecord? {
    guard let amount = double(row["earnings"]),
          amount > 0 else {
      return nil
    }

    let id = int(row["id"]) ?? index
    let date = date(row["started_at"]) ?? Date()
    let day = Calendar.current.startOfDay(for: date)
    return NativeRecord(
      legacyID: "json-trip-earnings-\(id)",
      kind: .income,
      platform: nonEmpty(string(row["platform"])),
      vehicle: nil,
      amount: amount,
      miles: nil,
      deduction: nil,
      category: nil,
      merchant: nil,
      date: date,
      period: .day,
      periodStart: day,
      periodEnd: day,
      receiptImageData: nil
    )
  }

  private static func legacyKeyValues(from rows: [[String: Any]]) -> [String: String] {
    rows.reduce(into: [:]) { result, row in
      guard let key = nonEmpty(string(row["key"])),
            let value = string(row["value"]) else { return }
      result[key] = value
    }
  }

  private static func applyAccountantDetails(_ values: [String: String], to settings: inout NativeSettings) {
    settings.accountantUTR = nonEmpty(values["utr"]) ?? ""
    settings.accountantNINumber = nonEmpty(values["ni_number"]) ?? ""
    settings.accountantAddress = nonEmpty(values["address"]) ?? ""
    settings.accountantBusinessDescription = nonEmpty(values["business_desc"]) ?? ""
  }

  private static func applyIncomeBracket(taxRate: Double?, to settings: inout NativeSettings) {
    guard let taxRate else { return }
    settings.incomeBracket = taxRate >= 0.40 ? .higher : .basic
  }

  private static func legacyTaxRate(from values: [String: String]) -> Double? {
    values["tax_rate"].flatMap { Double($0) }
  }

  private static func legacyOtherIncome(from values: [String: String]) -> Double? {
    values["other_income"].flatMap { Double($0) }
  }

  private static func routePoints(from raw: String?) -> [RoutePoint] {
    guard let raw,
          let data = raw.data(using: .utf8),
          let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }

    return values.compactMap { value in
      let latitude = double(value["lat"]) ?? double(value["latitude"])
      let longitude = double(value["lng"]) ?? double(value["longitude"])
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

  private static func string(_ value: Any?) -> String? {
    switch value {
    case let string as String:
      return string
    case let number as NSNumber:
      return number.stringValue
    default:
      return nil
    }
  }

  private static func nonEmpty(_ value: String?) -> String? {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return clean.isEmpty ? nil : clean
  }

  private static func double(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber:
      return number.doubleValue
    case let string as String:
      return Double(string)
    default:
      return nil
    }
  }

  private static func int(_ value: Any?) -> Int? {
    switch value {
    case let number as NSNumber:
      return number.intValue
    case let string as String:
      return Int(string)
    default:
      return nil
    }
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

  private static func date(_ value: Any?) -> Date? {
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

  private static func dateOnly(_ value: Any?) -> Date? {
    guard let raw = nonEmpty(string(value)) else { return nil }
    return legacyDateOnlyFormatter.date(from: String(raw.prefix(10))) ?? date(from: raw)
  }

  private static func uniqueTrips(_ trips: [NativeTrip]) -> [NativeTrip] {
    var seen = Set<String>()
    return trips.filter { trip in
      let key = trip.legacyID ?? "\(trip.vehicle.rawValue)-\(trip.startedAt.timeIntervalSince1970)-\(trip.miles)"
      guard !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
  }

  private static func uniqueRecords(_ records: [NativeRecord]) -> [NativeRecord] {
    var seen = Set<String>()
    return records.filter { record in
      let key = record.legacyID ?? "\(record.kind.rawValue)-\(record.date.timeIntervalSince1970)-\(record.amount ?? 0)-\(record.miles ?? 0)"
      guard !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
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
