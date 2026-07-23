import Foundation

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
      applySiriTripTracking(keyValues, to: &settings)

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
      applySiriTripTracking(keyValues, to: &settings)
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
      id: legacyTripUUID(id),
      legacyID: "json-trip-\(id)",
      source: .imported,
      vehicle: tripVehicle,
      miles: miles,
      deduction: storedDeduction > 0 ? storedDeduction : calculatedDeduction(miles: miles, vehicle: tripVehicle, date: startedAt),
      startedAt: startedAt,
      endedAt: date(row["ended_at"]) ?? startedAt,
      points: routePoints(from: string(row["route_json"])),
      feedback: string(row["feedback"]).flatMap(NativeTripFeedback.init(rawValue:))
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
      source: .imported,
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
      source: .tripEarnings,
      tripID: legacyTripUUID(id),
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

  private static func legacyTripUUID(_ id: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8002-%012llX", UInt64(id))) ?? UUID()
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

  private static func applySiriTripTracking(_ values: [String: String], to settings: inout NativeSettings) {
    guard let enabled = values["siri_trip_tracking_enabled"].flatMap({ Int($0) }) else { return }
    settings.siriTripTrackingEnabled = enabled != 0
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
