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

/// The tax jurisdiction the estimate runs under. `region` (rUK/Scotland) still
/// applies within the UK; `usState` applies within the US. Everything tax-side
/// — the tax-year window, the mileage rate, the calculation itself and the
/// on-screen labels — branches on this.
enum NativeTaxCountry: String, CaseIterable, Identifiable, Codable {
  case uk
  case us

  var id: String { rawValue }

  var label: String {
    switch self {
    case .uk: return "United Kingdom"
    case .us: return "United States"
    }
  }

  var currencyCode: String {
    switch self {
    case .uk: return "GBP"
    case .us: return "USD"
    }
  }
}

/// US states, for the state-income-tax layer. The five biggest gig markets
/// (CA, NY, IL, PA, GA) carry their own brackets/flat rates; the nine states
/// with no wage income tax resolve to zero; every other state falls back to a
/// flat rate the driver enters themselves (`otherState`) until per-state
/// brackets are added in a later release. All figures are for the 2025 tax
/// year and single filing status — they must be reviewed against official
/// state sources each year before shipping.
enum NativeUSState: String, CaseIterable, Identifiable, Codable {
  // Built-in brackets / flat rates.
  case california, newYork, illinois, pennsylvania, georgia
  // No wage income tax.
  case alaska, florida, nevada, southDakota, tennessee, texas, washington, wyoming, newHampshire
  // Anything else — user supplies a flat percentage in settings.
  case otherState

  var id: String { rawValue }

  var label: String {
    switch self {
    case .california: return "California"
    case .newYork: return "New York"
    case .illinois: return "Illinois"
    case .pennsylvania: return "Pennsylvania"
    case .georgia: return "Georgia"
    case .alaska: return "Alaska"
    case .florida: return "Florida"
    case .nevada: return "Nevada"
    case .southDakota: return "South Dakota"
    case .tennessee: return "Tennessee"
    case .texas: return "Texas"
    case .washington: return "Washington"
    case .wyoming: return "Wyoming"
    case .newHampshire: return "New Hampshire"
    case .otherState: return "Another state"
    }
  }

  /// True when this state levies no tax on ordinary wage / self-employment
  /// income, so the state layer is a hard zero regardless of profit.
  var hasNoIncomeTax: Bool {
    switch self {
    case .alaska, .florida, .nevada, .southDakota, .tennessee, .texas, .washington, .wyoming, .newHampshire:
      return true
    default:
      return false
    }
  }

  /// True when the app models this state's brackets itself; false means the
  /// driver's manually-entered flat rate is used instead.
  var hasBuiltInBrackets: Bool {
    switch self {
    case .california, .newYork, .illinois, .pennsylvania, .georgia:
      return true
    default:
      return false
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

/// Whether `location` is trustworthy enough to become a permanent vertex in
/// a recorded route (as opposed to just being accurate enough to update live
/// mileage/position). A single low-accuracy or GPS-multipath fix — accepted
/// by the much looser live-tracking filters — can otherwise bake a visible
/// zigzag spike into the route: the polyline jumps out to the bad point and
/// back on the very next real fix. Two independent checks: the fix itself
/// can't be too imprecise, and getting from the last recorded point to this
/// one can't imply an impossible speed (a GPS teleport, not real movement).
func nativeIsPlausibleRoutePoint(
  _ location: CLLocation,
  since lastRoutePointLocation: CLLocation?,
  maxAccuracyMeters: CLLocationDistance = 65,
  maxImpliedSpeedMetersPerSecond: Double = 45
) -> Bool {
  guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maxAccuracyMeters else { return false }
  guard let lastRoutePointLocation else { return true }
  let elapsed = location.timestamp.timeIntervalSince(lastRoutePointLocation.timestamp)
  guard elapsed > 0 else { return true }
  let distance = location.distance(from: lastRoutePointLocation)
  return distance / elapsed <= maxImpliedSpeedMetersPerSecond
}

enum NativeTripLocationRejectionReason: String, Equatable {
  case stale
  case beforeTrip
  case invalidAccuracy
  case inaccurate
  case outOfOrder
  case implausibleSpeed

  var diagnosticLabel: String {
    switch self {
    case .stale: return "stale timestamp"
    case .beforeTrip: return "timestamp before trip start"
    case .invalidAccuracy: return "invalid accuracy"
    case .inaccurate: return "accuracy over 65 m"
    case .outOfOrder: return "out-of-order timestamp"
    case .implausibleSpeed: return "implausible movement speed"
    }
  }
}

func nativeTripLocationRejectionReason(
  _ location: CLLocation,
  since previous: CLLocation?,
  now: Date = Date(),
  maximumAge: TimeInterval = 30,
  earliestTimestamp: Date? = nil,
  maxAccuracyMeters: CLLocationDistance = 65,
  maxImpliedSpeedMetersPerSecond: Double = 45
) -> NativeTripLocationRejectionReason? {
  let age = now.timeIntervalSince(location.timestamp)
  guard age <= maximumAge, age > -30 else { return .stale }
  if let earliestTimestamp, location.timestamp < earliestTimestamp { return .beforeTrip }
  guard location.horizontalAccuracy >= 0 else { return .invalidAccuracy }
  guard location.horizontalAccuracy <= maxAccuracyMeters else { return .inaccurate }
  guard let previous else { return nil }
  guard location.timestamp > previous.timestamp else { return .outOfOrder }

  let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
  let distance = location.distance(from: previous)
  guard distance / elapsed <= maxImpliedSpeedMetersPerSecond else { return .implausibleSpeed }
  return nil
}

/// A location used for mileage must meet the same quality bar as a location
/// drawn on the route. Keeping these paths aligned prevents mileage from
/// advancing through coarse fixes while the map is left with only a handful
/// of accurate vertices.
func nativeShouldAcceptTripLocation(
  _ location: CLLocation,
  since previous: CLLocation?,
  now: Date = Date(),
  maximumAge: TimeInterval = 30,
  earliestTimestamp: Date? = nil
) -> Bool {
  nativeTripLocationRejectionReason(
    location,
    since: previous,
    now: now,
    maximumAge: maximumAge,
    earliestTimestamp: earliestTimestamp
  ) == nil
}

/// When iOS leaves a large hole in the sampled route, a straight polyline is
/// not evidence of the streets actually driven. Start a new visible run so
/// the map shows an honest gap instead of cutting across several blocks.
func nativeRouteSegmentNeedsBreak(
  from previous: CLLocation,
  to current: CLLocation,
  maximumSegmentDistance: CLLocationDistance = 250,
  maximumSamplingGap: TimeInterval = 45
) -> Bool {
  let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
  guard elapsed > 0 else { return true }
  let distance = current.distance(from: previous)
  return distance > maximumSegmentDistance || (elapsed > maximumSamplingGap && distance > 80)
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
  // Optional raw CLLocation context. Older trips decode without this; newer
  // trips use it to avoid turning traffic-light waits into delivery stops.
  var horizontalAccuracy: Double? = nil
  var speed: Double? = nil
  var course: Double? = nil
  var vehicleConnectionActive: Bool? = nil

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case latitude
    case longitude
    case timestamp
    case breakBefore
    case horizontalAccuracy
    case speed
    case course
    case vehicleConnectionActive
  }

  init(
    id: UUID = UUID(),
    latitude: Double,
    longitude: Double,
    timestamp: Date? = nil,
    breakBefore: Bool = false,
    horizontalAccuracy: Double? = nil,
    speed: Double? = nil,
    course: Double? = nil,
    vehicleConnectionActive: Bool? = nil
  ) {
    self.id = id
    self.latitude = latitude
    self.longitude = longitude
    self.timestamp = timestamp
    self.breakBefore = breakBefore
    self.horizontalAccuracy = horizontalAccuracy
    self.speed = speed
    self.course = course
    self.vehicleConnectionActive = vehicleConnectionActive
  }

  init(location: CLLocation, vehicleConnectionActive: Bool? = nil, breakBefore: Bool = false) {
    self.init(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timestamp: location.timestamp,
      breakBefore: breakBefore,
      horizontalAccuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
      speed: location.speed >= 0 ? location.speed : nil,
      course: location.course >= 0 ? location.course : nil,
      vehicleConnectionActive: vehicleConnectionActive
    )
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    latitude = try container.decode(Double.self, forKey: .latitude)
    longitude = try container.decode(Double.self, forKey: .longitude)
    timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
    breakBefore = try container.decodeIfPresent(Bool.self, forKey: .breakBefore) ?? false
    horizontalAccuracy = try container.decodeIfPresent(Double.self, forKey: .horizontalAccuracy)
    speed = try container.decodeIfPresent(Double.self, forKey: .speed)
    course = try container.decodeIfPresent(Double.self, forKey: .course)
    vehicleConnectionActive = try container.decodeIfPresent(Bool.self, forKey: .vehicleConnectionActive)
  }
}

struct NativeRecord: Identifiable, Codable, Equatable {
  var id = UUID()
  var legacyID: String? = nil
  var updatedAt: Date? = nil
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
  var updatedAt: Date? = nil
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
  var feedback: NativeTripFeedback? = nil
  // Almost every trip logged here is a delivery, so business is the sane
  // default — the driver only ever has to act to flag the exception (an
  // errand auto-tracking picked up), not to classify every single trip.
  // Personal trips are kept, not deleted, and excluded from mileage/tax
  // totals and Insights instead — a complete log with excluded personal
  // miles is stronger evidence for an audit than one with entries quietly
  // removed, and it lets the total reconcile against the car's real mileage.
  var category: NativeTripCategory = .business
}

enum NativeTripCategory: String, CaseIterable, Identifiable, Codable {
  case business
  case personal

  var id: String { rawValue }
  var label: String { rawValue.capitalized }
}

enum NativeTripFeedback: String, CaseIterable, Identifiable, Codable {
  case good
  case bad

  var id: String { rawValue }

  var label: String {
    switch self {
    case .good: return "Good"
    case .bad: return "Bad"
    }
  }

  var symbol: String {
    switch self {
    case .good: return "hand.thumbsup.fill"
    case .bad: return "hand.thumbsdown.fill"
    }
  }
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
  /// Must stay comfortably above NativeAutoTrackEngine's
  /// minimumConnectedVehicleStopDwell (4 min) — that's the floor a stop has
  /// to clear before it's recorded at all when there's no vehicle-Bluetooth
  /// signal, so if this ceiling were at or below that floor, every such
  /// stop would already dwell past it and this branch could never fire,
  /// leaving every non-Bluetooth stop permanently misclassified as a
  /// pick-up. Verified via a real-day simulation that hit exactly that.
  var dropoffMaxDwellThreshold: TimeInterval = 600
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
    dropoffMaxDwellThreshold = try container.decodeIfPresent(TimeInterval.self, forKey: .dropoffMaxDwellThreshold) ?? 600
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
  // Tax jurisdiction. Defaults to the UK (the launch market); a US driver
  // switches this in Settings, which changes the tax-year window, the mileage
  // rate and the whole tax calculation. Decoded with a default so existing
  // UK snapshots (saved before this field existed) load as .uk.
  var taxCountry: NativeTaxCountry = .uk
  var region: NativeRegion = .ruk
  // US state for the state-income-tax layer (ignored when taxCountry == .uk).
  var usState: NativeUSState = .california
  // Flat state rate (as a fraction, e.g. 0.05 = 5%) used only when usState is
  // .otherState — a state Okkle doesn't yet model with its own brackets.
  var usOtherStateRate: Double = 0
  var incomeBracket: NativeIncomeBracket = .basic
  // UK: other PAYE income stacked under self-employment. US: W-2 wages, used
  // the same way (self-employment profit is taxed on top at the right bracket).
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
  // can use Car Audio disconnects and saved Home arrival to end
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
    case taxCountry
    case region
    case usState
    case usOtherStateRate
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
    taxCountry = try container.decodeIfPresent(NativeTaxCountry.self, forKey: .taxCountry) ?? .uk
    region = try container.decodeIfPresent(NativeRegion.self, forKey: .region) ?? .ruk
    usState = try container.decodeIfPresent(NativeUSState.self, forKey: .usState) ?? .california
    usOtherStateRate = try container.decodeIfPresent(Double.self, forKey: .usOtherStateRate) ?? 0
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

struct NativeDeletionTombstone: Codable, Equatable {
  var id: UUID
  var deletedAt: Date
}

struct NativeSnapshot: Codable {
  var settings: NativeSettings
  var records: [NativeRecord]
  var trips: [NativeTrip]
  var settingsUpdatedAt: Date?
  var recordTombstones: [NativeDeletionTombstone]
  var tripTombstones: [NativeDeletionTombstone]

  init(
    settings: NativeSettings,
    records: [NativeRecord],
    trips: [NativeTrip],
    settingsUpdatedAt: Date? = nil,
    recordTombstones: [NativeDeletionTombstone] = [],
    tripTombstones: [NativeDeletionTombstone] = []
  ) {
    self.settings = settings
    self.records = records
    self.trips = trips
    self.settingsUpdatedAt = settingsUpdatedAt
    self.recordTombstones = recordTombstones
    self.tripTombstones = tripTombstones
  }

  private enum CodingKeys: String, CodingKey {
    case settings
    case records
    case trips
    case settingsUpdatedAt
    case recordTombstones
    case tripTombstones
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    settings = try container.decode(NativeSettings.self, forKey: .settings)
    records = try container.decode([NativeRecord].self, forKey: .records)
    trips = try container.decode([NativeTrip].self, forKey: .trips)
    settingsUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .settingsUpdatedAt)
    recordTombstones = try container.decodeIfPresent(
      [NativeDeletionTombstone].self,
      forKey: .recordTombstones
    ) ?? []
    tripTombstones = try container.decodeIfPresent(
      [NativeDeletionTombstone].self,
      forKey: .tripTombstones
    ) ?? []
  }
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
