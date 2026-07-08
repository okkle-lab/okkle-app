import CoreLocation
import Foundation
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

enum NativeIncomeBracket: String, CaseIterable, Identifiable, Codable {
  case basic
  case higher

  var id: String { rawValue }

  var label: String {
    switch self {
    case .basic: return "Basic rate"
    case .higher: return "Higher rate"
    }
  }

  func marginalRate(region: NativeRegion) -> Double {
    switch (self, region) {
    case (.basic, _): return 0.20
    case (.higher, .ruk): return 0.40
    case (.higher, .scotland): return 0.42
    }
  }

  func assumedOtherIncome(region: NativeRegion) -> Double {
    switch self {
    case .basic:
      return 12_570
    case .higher:
      return region == .scotland ? 43_663 : 50_270
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
  // Optional (and absent from older saved trips) so decoding old data still
  // works — nil just means this point can't be used to attribute a specific
  // paid/dead leg within a multi-stop shift, only the trip's own total.
  var timestamp: Date? = nil
  // Marks a visible gap before this point, used when a driver removes a
  // middle route segment. Old trips decode with no gaps.
  var breakBefore = false

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case latitude
    case longitude
    case timestamp
    case breakBefore
  }

  init(
    id: UUID = UUID(),
    latitude: Double,
    longitude: Double,
    timestamp: Date? = nil,
    breakBefore: Bool = false
  ) {
    self.id = id
    self.latitude = latitude
    self.longitude = longitude
    self.timestamp = timestamp
    self.breakBefore = breakBefore
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    latitude = try container.decode(Double.self, forKey: .latitude)
    longitude = try container.decode(Double.self, forKey: .longitude)
    timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
    breakBefore = try container.decodeIfPresent(Bool.self, forKey: .breakBefore) ?? false
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
  var note: String? = nil
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
  // Reverse-geocoded lazily after the trip is saved (see
  // NativeTripAddressResolver) so the mileage log can show a real from/to
  // journey rather than just an aggregate distance. Nil until resolved, or
  // for trips saved before this existed.
  var startAddress: String? = nil
  var endAddress: String? = nil
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

enum NativeAppearanceMode: String, CaseIterable, Identifiable, Codable {
  case automatic
  case light
  case dark

  var id: String { rawValue }

  var label: String {
    switch self {
    case .automatic: return "Auto"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }
}

/// A place the driver has told us isn't a work stop — home, a regular break
/// spot, a partner's address — so it never gets suggested back to them as
/// somewhere to go and earn.
struct NativeExcludedPlace: Codable, Identifiable, Equatable {
  var id = UUID()
  var label: String
  var latitude: Double
  var longitude: Double
  var address: String?

  var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Tunable thresholds behind automatic shift/stop detection — starts at sane
/// defaults and nudges itself from the driver's own corrections in the
/// shift-review screen, so accuracy keeps improving per-driver rather than
/// staying pinned to one global guess forever.
struct NativeAutoTrackCalibration: Codable, Equatable {
  /// How long stationary before a shift is considered over.
  var stationaryTimeoutSeconds: TimeInterval = 20 * 60
  /// Provisional pickup guess: dwell at or above this reads as a pick-up.
  var pickupDwellThreshold: TimeInterval = 150
  /// Below this dwell, with no nearby food venue, MapKit confirms drop-off.
  var dropoffMaxDwellThreshold: TimeInterval = 240
  /// Search radius for a nearby restaurant/cafe when refining a stop's kind.
  var foodPoiRadiusMeters: Double = 45

  private enum CodingKeys: String, CodingKey {
    case stationaryTimeoutSeconds
    case pickupDwellThreshold
    case dropoffMaxDwellThreshold
    case foodPoiRadiusMeters
  }

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    stationaryTimeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .stationaryTimeoutSeconds) ?? 20 * 60
    pickupDwellThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .pickupDwellThreshold) ?? 150
    dropoffMaxDwellThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .dropoffMaxDwellThreshold) ?? 240
    foodPoiRadiusMeters = try container.decodeIfPresent(Double.self, forKey: .foodPoiRadiusMeters) ?? 45
  }

  /// Nudge, don't overwrite — one outlier correction shouldn't swing the
  /// threshold wildly. 80% old / 20% new per correction, clamped to a
  /// sane range so a single bad data point can't break detection.
  mutating func nudgeStationaryTimeout(toward suggested: TimeInterval) {
    let blended = stationaryTimeoutSeconds * 0.8 + suggested * 0.2
    stationaryTimeoutSeconds = min(max(blended, 8 * 60), 60 * 60)
  }
}

struct NativeSettings: Codable, Equatable {
  var name = ""
  var defaultVehicle: NativeVehicle = .car
  var region: NativeRegion = .ruk
  var incomeBracket: NativeIncomeBracket = .basic
  var otherIncome: Double = 0
  var platforms = ["Uber Eats", "Deliveroo", "Just Eat"]
  var accountantUTR = ""
  var accountantNINumber = ""
  var accountantAddress = ""
  var accountantBusinessDescription = ""
  var loggingReminder = true
  var reminderDay = 1
  var logFrequency: NativeLogFrequency = .weekly
  var taxDeadlineReminders = true
  var appearanceMode: NativeAppearanceMode = .automatic
  // Master switch for the AI Insights tab and insight-led prompts.
  var insightsEnabled = true
  // Optional iCloud sync. Kept in settings so the preference follows the
  // user's Okkle snapshot once sync is enabled.
  var iCloudSyncEnabled = false
  // Automatic trip tracking: on by default, tracking any trip. `workingDays`
  // holds the weekdays (0 = Sunday … 6 = Saturday, matching Calendar's symbol
  // index) on which trips auto-start; default is every day.
  var autoTrackTrips = true
  // Adds stronger vehicle signals to automatic tracking. When enabled, Okkle
  // can use CarPlay / car Bluetooth disconnects and saved Home arrival to end
  // trips with less GPS tail.
  var enhancedAutoTracking = true
  // Opt-in voice automation: lets Siri and Shortcuts start or resume tracking
  // with the driver's default vehicle.
  var siriTripTrackingEnabled = false
  var workingDays: [Int] = Array(0...6)
  // A heads-up before your busy window starts, on working days.
  var preShiftAlerts = true
  // Manual trips still ask before ending by default. When enabled, the same
  // stationary detection quietly completes the trip after the driver stops.
  var manualTripAutoComplete = false
  var hasCompletedOnboarding = false
  // Places the driver has manually marked as not-work (home, a usual break
  // spot) — kept out of the "where to go" earning suggestions. If this is
  // empty, the app falls back to auto-detecting a likely home location from
  // dwell patterns (see nativeDetectedHomeCoordinate).
  var excludedPlaces: [NativeExcludedPlace] = []
  // Self-tuning thresholds behind automatic shift/stop detection.
  var autoTrackCalibration = NativeAutoTrackCalibration()

  init() {}

  private enum CodingKeys: String, CodingKey {
    case name
    case defaultVehicle
    case region
    case incomeBracket
    case otherIncome
    case platforms
    case accountantUTR
    case accountantNINumber
    case accountantAddress
    case accountantBusinessDescription
    case loggingReminder
    case reminderDay
    case logFrequency
    case taxDeadlineReminders
    case appearanceMode
    case insightsEnabled
    case iCloudSyncEnabled
    case autoTrackTrips
    case enhancedAutoTracking
    case siriTripTrackingEnabled
    case workingDays
    case preShiftAlerts
    case manualTripAutoComplete
    case hasCompletedOnboarding
    case excludedPlaces
    case autoTrackCalibration
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    defaultVehicle = try container.decodeIfPresent(NativeVehicle.self, forKey: .defaultVehicle) ?? .car
    region = try container.decodeIfPresent(NativeRegion.self, forKey: .region) ?? .ruk
    incomeBracket = try container.decodeIfPresent(NativeIncomeBracket.self, forKey: .incomeBracket) ?? .basic
    otherIncome = try container.decodeIfPresent(Double.self, forKey: .otherIncome) ?? 0
    platforms = try container.decodeIfPresent([String].self, forKey: .platforms) ?? ["Uber Eats", "Deliveroo", "Just Eat"]
    accountantUTR = try container.decodeIfPresent(String.self, forKey: .accountantUTR) ?? ""
    accountantNINumber = try container.decodeIfPresent(String.self, forKey: .accountantNINumber) ?? ""
    accountantAddress = try container.decodeIfPresent(String.self, forKey: .accountantAddress) ?? ""
    accountantBusinessDescription = try container.decodeIfPresent(String.self, forKey: .accountantBusinessDescription) ?? ""
    loggingReminder = try container.decodeIfPresent(Bool.self, forKey: .loggingReminder) ?? true
    reminderDay = try container.decodeIfPresent(Int.self, forKey: .reminderDay) ?? 1
    logFrequency = try container.decodeIfPresent(NativeLogFrequency.self, forKey: .logFrequency) ?? .weekly
    taxDeadlineReminders = try container.decodeIfPresent(Bool.self, forKey: .taxDeadlineReminders) ?? true
    appearanceMode = try container.decodeIfPresent(NativeAppearanceMode.self, forKey: .appearanceMode) ?? .automatic
    insightsEnabled = try container.decodeIfPresent(Bool.self, forKey: .insightsEnabled) ?? true
    iCloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? false
    autoTrackTrips = try container.decodeIfPresent(Bool.self, forKey: .autoTrackTrips) ?? true
    enhancedAutoTracking = try container.decodeIfPresent(Bool.self, forKey: .enhancedAutoTracking) ?? true
    siriTripTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .siriTripTrackingEnabled) ?? false
    workingDays = try container.decodeIfPresent([Int].self, forKey: .workingDays) ?? Array(0...6)
    preShiftAlerts = try container.decodeIfPresent(Bool.self, forKey: .preShiftAlerts) ?? true
    manualTripAutoComplete = try container.decodeIfPresent(Bool.self, forKey: .manualTripAutoComplete) ?? false
    hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    excludedPlaces = try container.decodeIfPresent([NativeExcludedPlace].self, forKey: .excludedPlaces) ?? []
    autoTrackCalibration = try container.decodeIfPresent(NativeAutoTrackCalibration.self, forKey: .autoTrackCalibration) ?? NativeAutoTrackCalibration()
  }
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

struct NativeBackupRestoreSummary {
  var records: Int
  var trips: Int

  var message: String {
    "Restored \(records) records and \(trips) trips from backup."
  }
}

enum NativeBackupRestoreError: LocalizedError {
  case invalidBackup
  case iCloudSyncEnabled

  var errorDescription: String? {
    switch self {
    case .invalidBackup:
      return "That file does not look like an Okkle backup."
    case .iCloudSyncEnabled:
      return "Turn off iCloud sync before restoring a backup."
    }
  }
}
