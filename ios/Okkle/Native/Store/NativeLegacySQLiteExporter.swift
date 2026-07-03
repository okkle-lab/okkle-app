import Foundation
import SQLite3

private let nativeSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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

    return addColumnIfMissing("region TEXT DEFAULT 'ruk'", named: "region", to: "user", in: db) &&
      addColumnIfMissing("reminder_enabled INTEGER DEFAULT 1", named: "reminder_enabled", to: "user", in: db) &&
      addColumnIfMissing("reminder_day TEXT DEFAULT 'sun'", named: "reminder_day", to: "user", in: db) &&
      addColumnIfMissing("log_frequency TEXT DEFAULT 'weekly'", named: "log_frequency", to: "user", in: db) &&
      addColumnIfMissing("zone TEXT", named: "zone", to: "trips", in: db) &&
      addColumnIfMissing("vehicles TEXT", named: "vehicles", to: "user", in: db) &&
      addColumnIfMissing("vehicle TEXT", named: "vehicle", to: "records", in: db)
  }

  private static func addColumnIfMissing(_ definition: String, named column: String, to table: String, in db: OpaquePointer) -> Bool {
    columnExists(column, in: table, db: db) || exec("ALTER TABLE \(table) ADD COLUMN \(definition)", in: db)
  }

  private static func columnExists(_ column: String, in table: String, db: OpaquePointer) -> Bool {
    withStatement("PRAGMA table_info(\(table))", in: db) { statement in
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let namePointer = sqlite3_column_text(statement, 1) else { continue }
        if String(cString: namePointer).caseInsensitiveCompare(column) == .orderedSame {
          return true
        }
      }
      return false
    }
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
      ("siri_trip_tracking_enabled", settings.siriTripTrackingEnabled ? "1" : "0"),
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
