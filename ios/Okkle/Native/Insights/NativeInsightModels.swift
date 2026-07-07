import CoreLocation
import Foundation

enum NativeTimeFilter: String, CaseIterable, Identifiable {
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

  var startHour: Int? {
    switch self {
    case .all: return nil
    case .morning: return 6
    case .lunch: return 11
    case .afternoon: return 14
    case .dinner: return 17
    case .late: return 21
    }
  }

  /// A clock range for the band — so the UI can show *when*, not a vague label.
  var timeRange: String {
    switch self {
    case .all: return "All day"
    case .morning: return "6–11am"
    case .lunch: return "11am–2pm"
    case .afternoon: return "2–5pm"
    case .dinner: return "5–9pm"
    case .late: return "9pm–late"
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

// MARK: - Zone colour scale

/// Quiet → busiest, in one clear ramp (cool blue → teal → green → amber → red)
/// instead of a single colour at varying opacity, so a glance tells you which
/// zones and times are actually worth being in.

struct NativeShiftWindow: Identifiable, Equatable {
  let weekday: Int   // 0 = Sunday … 6 = Saturday
  let band: NativeTimeFilter
  let count: Int
  let sharePct: Int

  var id: String { "\(weekday)|\(band.rawValue)" }
  var label: String { "\(Calendar.current.shortWeekdaySymbols[weekday]) \(band.label.lowercased())" }
}

/// Guesses where "home" is from raw dwell time alone — every visit counts,
/// regardless of pick-up/drop-off classification, because a courier is
/// stationary at home for hours most days, far longer than any real delivery
/// stop. Needs 4+ cumulative hours in one ~500m cell before it'll commit to a
/// guess, so a new driver's first few days of real routes aren't mistaken
/// for a homebound pattern.
func nativeDetectedHomeCoordinate(_ visits: [NativeVisit]) -> CLLocationCoordinate2D? {
  guard !visits.isEmpty else { return nil }
  let cellSize = 0.006
  var cells: [String: (coordinate: CLLocationCoordinate2D, totalDwell: TimeInterval)] = [:]
  for visit in visits {
    let key = "\(Int((visit.coordinate.latitude / cellSize).rounded())),\(Int((visit.coordinate.longitude / cellSize).rounded()))"
    var cell = cells[key] ?? (visit.coordinate, 0)
    cell.totalDwell += visit.dwell
    cells[key] = cell
  }
  guard let top = cells.values.max(by: { $0.totalDwell < $1.totalDwell }), top.totalDwell >= 4 * 3600 else { return nil }
  return top.coordinate
}

/// A clustered zone of pick-up/drop-off activity, for colouring the map by how
/// busy each area has been — not a real-time heatmap, just your own history.
struct NativeZonePoint: Identifiable, Equatable {
  let id = UUID()
  let coordinate: CLLocationCoordinate2D
  let weight: Double   // 0 (quiet) ... 1 (your busiest zone) — popularity blended with efficiency and, while evidence is thin, a food-POI-density prior
  var count: Int = 0   // raw deliveries in this cluster
  var peakHour: Int? = nil   // the hour this area is busiest for you
  var deadMilePct: Int? = nil   // % of the miles to reach this zone that were unpaid repositioning

  /// A tight "when to go" window around the area's busiest hour.
  var timeLabel: String? {
    guard let h = peakHour else { return nil }
    return "\(nativeHourLabel(h))–\(nativeHourLabel(h + 2))"
  }

  static func == (lhs: NativeZonePoint, rhs: NativeZonePoint) -> Bool {
    lhs.id == rhs.id
  }
}

/// Ranked, de-duplicated areas near the driver — the "where to go" shortlist.
/// Keeps at most `limit`, prefers busier zones, drops anything absurdly far.
func nativeTopZones(_ zones: [NativeZonePoint], near origin: CLLocationCoordinate2D?, limit: Int = 5, maxKm: Double = 12) -> [NativeZonePoint] {
  var candidates = zones
  if let origin {
    let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
    candidates = zones.filter {
      here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) <= maxKm * 1000
    }
    if candidates.isEmpty { candidates = zones }   // never leave them with nothing
  }
  return Array(candidates.sorted { $0.weight > $1.weight }.prefix(limit))
}

/// One named, ranked area — the shared source of truth so the "where to go"
/// list and the map pins carry the *same* number for the *same* place.
struct NativeRankedArea: Identifiable {
  let id = UUID()
  let rank: Int
  let name: String
  let time: String?
  let coordinate: CLLocationCoordinate2D
  let weight: Double
}

/// Rank the busiest patches that have a resolved name, 1…limit. Both the list
/// and the map build from this, so pin "2" and list row "2" are the same place.
@MainActor
func nativeRankedAreas(_ zones: [NativeZonePoint], near origin: CLLocationCoordinate2D?, namer: NativeAreaNamer, limit: Int) -> [NativeRankedArea] {
  let top = nativeTopZones(zones, near: origin, limit: limit + 4)
  var seen = Set<String>()
  var out: [NativeRankedArea] = []
  for zone in top {
    guard let name = namer.name(for: zone.coordinate) else { continue }
    if seen.insert(name).inserted {
      out.append(NativeRankedArea(rank: out.count + 1, name: name, time: zone.timeLabel,
                                  coordinate: zone.coordinate, weight: zone.weight))
    }
    if out.count >= limit { break }
  }
  return out
}

/// How many deliveries land on one weekday, for the weekly overview bar list.
struct NativeWeekdayStat: Identifiable, Equatable {
  let weekday: Int   // 0 = Sunday … 6 = Saturday
  let count: Int
  let sharePct: Int

  var id: Int { weekday }
  var symbol: String { Calendar.current.veryShortWeekdaySymbols[weekday] }
  var name: String { Calendar.current.weekdaySymbols[weekday] }
}

/// "6pm", "12pm", "1am" — a compact clock label for one hour of the day.
func nativeHourLabel(_ hour: Int) -> String {
  let h = ((hour % 24) + 24) % 24
  let suffix = h < 12 ? "am" : "pm"
  var twelve = h % 12
  if twelve == 0 { twelve = 12 }
  return "\(twelve)\(suffix)"
}

/// A contiguous run of busy (or, for a break, quiet) hours: "6–9pm".
struct NativeHourWindow: Identifiable, Equatable {
  let startHour: Int
  let endHour: Int   // inclusive last hour
  let count: Int

  var id: Int { startHour }
  var label: String { "\(nativeHourLabel(startHour))–\(nativeHourLabel(endHour + 1))" }
}

/// Per-weekday summary for the weekly panel: best band, roughly where, and how
/// busy — so "this week" can say *when and where* each day was good.
struct NativeWeekdayDetail: Identifiable, Equatable {
  let weekday: Int
  let band: NativeTimeFilter
  let count: Int
  let coordinate: CLLocationCoordinate2D?
  let deadMilePct: Int?   // unpaid miles as a % of this weekday's own driving

  var id: Int { weekday }
  var name: String { Calendar.current.weekdaySymbols[weekday] }
  var shortName: String { Calendar.current.shortWeekdaySymbols[weekday] }

  static func == (lhs: NativeWeekdayDetail, rhs: NativeWeekdayDetail) -> Bool {
    lhs.weekday == rhs.weekday && lhs.band == rhs.band && lhs.count == rhs.count
  }
}

/// A same-day plan: the best window to work, a natural lull worth treating as
/// a break, and roughly where the work has been — built from your own history
/// for that specific weekday, not the whole week averaged together.
struct NativeDayPlan {
  let weekday: Int
  let isToday: Bool
  let deliveries: Int
  let bestBand: NativeTimeFilter?
  let breakBand: NativeTimeFilter?
  let zone: CLLocationCoordinate2D?
  let hourCounts: [Int]              // 24 buckets of delivery counts for this day
  let driveWindows: [NativeHourWindow]
  let breakWindow: NativeHourWindow?

  var dayLabel: String { isToday ? "Today" : Calendar.current.weekdaySymbols[weekday] }

  /// The busiest drive window (most deliveries) — the one to anchor the day on.
  var peakWindow: NativeHourWindow? { driveWindows.max { $0.count < $1.count } }
}

/// A short "how did that shift go" read on your most recent logged day: the
/// day's £/hr versus your usual for that weekday, and whether you clocked off
/// before your typical peak.
struct NativeShiftDebrief {
  let weekday: Int
  let perHour: Double
  let weekdayAvgPerHour: Double?
  let finishedBeforePeak: Bool
  let peakLabel: String?

  var dayName: String { Calendar.current.shortWeekdaySymbols[weekday] }

  /// Comparative read only — never exact accounting. The £/hr values behind
  /// this are modelled from weekly pay spread over inferred hours.
  var comparative: String? {
    guard let avg = weekdayAvgPerHour, avg > 0 else { return nil }
    let ratio = perHour / avg
    switch ratio {
    case 1.15...: return "Your last \(dayName) was well above your usual."
    case 1.03..<1.15: return "Your last \(dayName) was a touch above your usual."
    case 0.85..<1.03: return "Your last \(dayName) was around your usual."
    default: return "Your last \(dayName) was below your usual."
    }
  }

  var wasUp: Bool { (weekdayAvgPerHour ?? perHour) <= perHour }
}

/// Whether a weekday's volume looks the same week to week, or is dominated by
/// occasional big/quiet weeks — the per-day counterpart to overall confidence.
enum NativeDayReliability {
  case reliable, erratic
}

/// One platform's real, logged share of income this period — the ranked
/// counterpart to the single "top platform" line, only ever populated when
/// there's an actual mix (2+ platforms) to rank.
struct NativePlatformShare: Identifiable {
  let id = UUID()
  let platform: String
  let sharePct: Int
  let deltaPct: Int?   // vs the same platform's share last period, if meaningful
}

/// How much evidence sits behind a recommendation. The engine should know when
/// not to make a strong claim — thin data gets soft language, never certainty.
enum NativeConfidence {
  case low, medium, high

  var tag: String {
    switch self {
    case .low: return "EARLY READ"
    case .medium: return "GOOD READ"
    case .high: return "SOLID PATTERN"
    }
  }

  var dots: Int {
    switch self {
    case .low: return 1
    case .medium: return 2
    case .high: return 3
    }
  }

  /// Plain-words strength for the header chip — "Confidence: High".
  var level: String {
    switch self {
    case .low: return "Low"
    case .medium: return "Medium"
    case .high: return "High"
    }
  }
}

/// Everything the passive engine can tell a driver, derived from the stops plus
/// their (weekly) logged income. Aggregate totals stay exact; only the
/// within-week distribution is modelled, so estimates are bounded.
struct NativeShiftInsights {
  let deliveries: Int
  let activeHours: Double
  let paidMiles: Double
  let deadMiles: Double
  let bestWindow: String?
  let perHour: Double?
  let windows: [NativeShiftWindow]
  let quietWindow: NativeShiftWindow?
  let zones: [NativeZonePoint]
  let weekdayStats: [NativeWeekdayStat]
  let weekdayDetails: [NativeWeekdayDetail]   // active days, busiest first
  let todayPlan: NativeDayPlan?
  let lastShift: NativeShiftDebrief?
  let activeDays: Int                          // distinct days with tracked stops
  let daySpan: Int                             // calendar days from the first tracked stop to the last
  let peakHitRate: Double?                     // how often "your peak" has actually paid off
  let weekdayReliability: [Int: NativeDayReliability]   // per-weekday, week-to-week consistency
  let platformShares: [NativePlatformShare]             // ranked, only populated with 2+ platforms logged
  let hourCounts: [Int]                                 // 24 buckets: all deliveries in the period by hour of day

  var hasData: Bool { deliveries > 0 }
  var totalMiles: Double { paidMiles + deadMiles }
  var deadMilePct: Int {
    guard totalMiles > 0 else { return 0 }
    return Int((deadMiles / totalMiles * 100).rounded())
  }

  /// Overall evidence level: enough deliveries across enough distinct days,
  /// spread over enough real time, *and* those days actually look alike.
  /// Sample size alone can be misleading two different ways: five visits
  /// that all landed near the same volume is a genuinely repeatable
  /// pattern; five visits where one outlier day did most of the work is
  /// really a single fluke wearing a big-sample-size costume; and eight
  /// deliveries crammed into three back-to-back days says nothing about
  /// which days of the week are actually busiest, even though the raw
  /// counts alone would already clear the bar. The day-to-day spread
  /// (coefficient of variation across active weekdays) catches the first
  /// problem; requiring the evidence to span at least a week (a fortnight
  /// for "high") catches the second.
  var confidence: NativeConfidence {
    var level: NativeConfidence
    if deliveries >= 20 && activeDays >= 6 && daySpan >= 14 { level = .high }
    else if deliveries >= 8 && activeDays >= 3 && daySpan >= 7 { level = .medium }
    else { level = .low }

    if level != .low {
      let counts = weekdayStats.filter { $0.count > 0 }.map { Double($0.count) }
      if counts.count >= 2 {
        let mean = counts.reduce(0, +) / Double(counts.count)
        if mean > 0 {
          let variance = counts.reduce(0) { $0 + pow($1 - mean, 2) } / Double(counts.count)
          let coefficientOfVariation = sqrt(variance) / mean
          // Roughly: one day carrying most of the volume (CV > ~1.1) downgrades
          // two steps; a noticeably lopsided week (CV > ~0.75) downgrades one
          // step from "high" only — a bit of natural variation shouldn't
          // punish "medium".
          if coefficientOfVariation > 1.1 { level = (level == .high) ? .medium : .low }
          else if coefficientOfVariation > 0.75 && level == .high { level = .medium }
        }
      }
    }

    // Has "your peak" actually been paying off? Only ever downgrades — a
    // good hit rate doesn't inflate confidence beyond what the sample size
    // and consistency already earned, per the same restraint as elsewhere.
    if let hitRate = peakHitRate, level != .low {
      if hitRate < 0.35 { level = .low }
      else if hitRate < 0.5 && level == .high { level = .medium }
    }

    return level
  }

  /// Rough shifts still needed before the pattern firms up (low confidence only).
  var shiftsToSharpen: Int { max(1, 3 - min(activeDays, 3) + (deliveries < 8 ? 1 : 0)) }

  /// £/hr as an honest range, never a fake-precise figure — the underlying
  /// value is weekly pay spread over inferred active hours.
  var perHourBand: String? {
    guard let perHour, perHour > 0 else { return nil }
    let lower = Int((perHour * 0.85 / 1).rounded(.down))
    let upper = Int((perHour * 1.15 / 1).rounded(.up))
    return "£\(lower)–\(upper)"
  }

  /// The single most useful warning — one only, per the "instruction beats
  /// dashboards" principle.
  var warning: String? {
    if deadMilePct >= 25 {
      return "About \(deadMilePct)% of your miles are unpaid roaming — wait nearer a pick-up zone between orders."
    }
    if let quiet = quietWindow, confidence != .low {
      return "\(quiet.label.capitalized) is usually weak for you — worth resting or trying elsewhere."
    }
    if perHour == nil {
      return "Log your pay after a shift to unlock an earnings-rate estimate."
    }
    return nil
  }

  private static let routeDistanceNormalizationFactor = 1.3

  static let empty = NativeShiftInsights(
    deliveries: 0, activeHours: 0, paidMiles: 0, deadMiles: 0,
    bestWindow: nil, perHour: nil, windows: [], quietWindow: nil, zones: [],
    weekdayStats: [], weekdayDetails: [], todayPlan: nil, lastShift: nil,
    activeDays: 0, daySpan: 0, peakHitRate: nil, weekdayReliability: [:],
    platformShares: [], hourCounts: Array(repeating: 0, count: 24)
  )

  static func enrichedVisits(visits: [NativeVisit], trips: [NativeTrip]) -> [NativeVisit] {
    let synthetic = trips.flatMap { trip in
      tripDerivedVisits(for: trip, existingVisits: visits)
    }
    guard !synthetic.isEmpty else { return visits }
    return (visits + synthetic).sorted { left, right in left.arrival < right.arrival }
  }

  private static func tripDerivedVisits(for trip: NativeTrip, existingVisits: [NativeVisit]) -> [NativeVisit] {
    guard trip.endedAt > trip.startedAt, trip.miles > 0 else { return [] }
    let overlappingVisits = existingVisits.filter { visit in
      visit.arrival <= trip.endedAt && visit.departure >= trip.startedAt
    }
    guard let start = trip.points.first?.coordinate, let end = trip.points.last?.coordinate else { return [] }
    let inferredStops = routeDerivedStops(for: trip, start: start, end: end)
      .filter { !NativeRouteStopDetector.containsSameStop(overlappingVisits, $0) }
    if !inferredStops.isEmpty {
      return inferredStops
    }
    guard overlappingVisits.isEmpty else { return [] }

    let pickupDeparture = trip.startedAt
    let dropArrival = trip.endedAt

    var pickup = NativeVisit(
      id: deterministicUUID(seed: "\(trip.id.uuidString)-pickup"),
      latitude: start.latitude,
      longitude: start.longitude,
      arrival: trip.startedAt,
      departure: pickupDeparture,
      kindRaw: NativeVisit.Kind.pickup.rawValue,
      placeName: "Trip start",
      isEndpointGuess: true
    )
    pickup.kind = .pickup

    var dropoff = NativeVisit(
      id: deterministicUUID(seed: "\(trip.id.uuidString)-dropoff"),
      latitude: end.latitude,
      longitude: end.longitude,
      arrival: dropArrival,
      departure: trip.endedAt,
      kindRaw: NativeVisit.Kind.dropoff.rawValue,
      placeName: "Trip end",
      isEndpointGuess: true
    )
    dropoff.kind = .dropoff

    return [pickup, dropoff]
  }

  private static func routeDerivedStops(
    for trip: NativeTrip,
    start: CLLocationCoordinate2D,
    end: CLLocationCoordinate2D
  ) -> [NativeVisit] {
    var visits = NativeRouteStopDetector.detectStops(in: trip.points).map(\.visit)
    guard !visits.isEmpty else { return [] }

    if visits.count == 1 {
      visits[0].kind = .dropoff
      visits[0].placeName = "Detected stop"
      return [tripEndpointVisit(
        trip: trip,
        coordinate: start,
        date: trip.startedAt,
        role: .pickup,
        suffix: "pickup",
        name: "Trip start"
      ), visits[0]]
    }

    for index in visits.indices {
      visits[index].kind = index.isMultiple(of: 2) ? .pickup : .dropoff
      visits[index].placeName = visits[index].kind == .pickup ? "Detected pick-up" : "Detected drop-off"
    }

    if visits.last?.kind == .pickup {
      visits.append(tripEndpointVisit(
        trip: trip,
        coordinate: end,
        date: trip.endedAt,
        role: .dropoff,
        suffix: "dropoff",
        name: "Trip end"
      ))
    }

    return visits
  }

  private static func tripEndpointVisit(
    trip: NativeTrip,
    coordinate: CLLocationCoordinate2D,
    date: Date,
    role: NativeVisit.Kind,
    suffix: String,
    name: String
  ) -> NativeVisit {
    var visit = NativeVisit(
      id: deterministicUUID(seed: "\(trip.id.uuidString)-\(suffix)"),
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
      arrival: date,
      departure: date,
      kindRaw: role.rawValue,
      placeName: name
    )
    visit.kind = role
    return visit
  }

  private static func deterministicUUID(seed: String) -> UUID {
    var first: UInt64 = 0xcbf29ce484222325
    var second: UInt64 = 0x84222325cbf29ce4
    for byte in seed.utf8 {
      first ^= UInt64(byte)
      first &*= 0x100000001b3
      second ^= UInt64(byte) &+ 0x9e3779b97f4a7c15
      second &*= 0x100000001b3
    }
    let a = UInt32(truncatingIfNeeded: first >> 32)
    let b = UInt16(truncatingIfNeeded: first >> 16)
    let c = UInt16(truncatingIfNeeded: first)
    let d = UInt16(truncatingIfNeeded: second >> 48)
    let e = second & 0x0000ffffffffffff
    return UUID(uuidString: String(format: "%08X-%04X-%04X-%04X-%012llX", a, b, c, d, e)) ?? UUID()
  }

  @MainActor
  static func build(visits: [NativeVisit], store: OkkleStore) -> NativeShiftInsights {
    // Kept out of every calculation below, not just "where to go": places the
    // driver manually flagged, plus an auto-detected home guess when they
    // haven't set anything themselves. Left in, a night at home next to a
    // short gap before the morning's first stop reads as one continuous
    // "active" chain — home's whole dwell gets counted as work time, which
    // wrecks activeHours and therefore £/hr. Manual entries always apply too
    // — labelling one spot doesn't turn off the auto-guess for a *different*
    // long-dwell place (e.g. a partner's).
    var notWorkCoordinates = store.settings.excludedPlaces.map(\.coordinate)
    if let home = nativeDetectedHomeCoordinate(visits) { notWorkCoordinates.append(home) }
    let exclusionRadiusMeters = 200.0
    func isExcluded(_ coordinate: CLLocationCoordinate2D) -> Bool {
      let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
      return notWorkCoordinates.contains { point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= exclusionRadiusMeters }
    }

    let sorted = visits.sorted { $0.arrival < $1.arrival }.filter { !isExcluded($0.coordinate) }
    guard sorted.count > 1 else { return .empty }

    let roadFactor = 1.3
    let shiftGap: TimeInterval = 45 * 60   // a gap longer than this ends a shift

    // Total distance + active time across legs within a shift. Real route
    // distance from a recorded trip's GPS points when one covers this leg —
    // only falls back to the straight-line estimate when no trip data exists
    // for it (older data, or a stop outside any recorded shift).
    var totalMeters = 0.0
    var activeSeconds = 0.0
    var totalMetersByWeekday: [Int: Double] = [:]
    for k in 1..<sorted.count {
      let prev = sorted[k - 1], cur = sorted[k]
      let gap = cur.arrival.timeIntervalSince(prev.departure)
      if gap < shiftGap {
        let legMeters = routeMeters(from: prev.departure, to: cur.arrival, trips: store.trips)
          ?? cur.location.distance(from: prev.location)
        totalMeters += legMeters
        let legWeekday = Calendar.current.component(.weekday, from: cur.arrival) - 1
        totalMetersByWeekday[legWeekday, default: 0] += legMeters
        activeSeconds += max(0, gap) + prev.dwell
      }
    }
    activeSeconds += sorted.last?.dwell ?? 0

    // Deliveries + paid distance: a pick-up drives to the next drop-off.
    var deliveries = 0
    var paidMeters = 0.0
    var paidMetersByWeekday: [Int: Double] = [:]
    var deliveryHits: [NativeDeliveryHit] = []
    var index = 0
    while index < sorted.count {
      if sorted[index].kind == .pickup,
         let dropIndex = (index + 1..<sorted.count).first(where: { sorted[$0].kind == .dropoff }) {
        deliveries += 1
        // Paid = the active delivery leg (restaurant → customer). Everything
        // else (repositioning back out to the next pick-up, idle wandering) is
        // unpaid mileage. Real route distance when a recorded trip covers this
        // leg, otherwise a straight-line estimate.
        let legMeters = routeMeters(from: sorted[index].departure, to: sorted[dropIndex].arrival, trips: store.trips)
          ?? sorted[dropIndex].location.distance(from: sorted[index].location)
        paidMeters += legMeters
        let date = sorted[dropIndex].arrival
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        paidMetersByWeekday[weekday, default: 0] += legMeters
        let hour = Calendar.current.component(.hour, from: date)
        let band = NativeTimeFilter.allCases.first { $0 != .all && $0.includes(date) } ?? .afternoon
        // A pair built from a trip's raw start/end point (no real classified
        // stop) still counts toward deliveries/mileage/timing above, but its
        // coordinate is just "wherever the shift happened to start" — usually
        // home for a home-based driver — so it's excluded from zone/place
        // ranking below rather than risk recommending home, or a random
        // waypoint, as "where to go".
        let isLocationTrustworthy = !sorted[index].isEndpointGuess && !sorted[dropIndex].isEndpointGuess
        // How far it took to reposition back into this pickup zone from
        // whatever came before it — the same unpaid-mileage cost the overall
        // deadMiles figure already counts, just attributed to this specific
        // zone so "busiest" can be weighed against "cheapest to reach".
        var approachMeters = 0.0
        if index > 0 {
          let prev = sorted[index - 1]
          let gap = sorted[index].arrival.timeIntervalSince(prev.departure)
          if gap < shiftGap {
            approachMeters = routeMeters(from: prev.departure, to: sorted[index].arrival, trips: store.trips)
              ?? sorted[index].location.distance(from: prev.location)
          }
        }
        // The actual vehicle logged for whichever trip covered this delivery
        // — a bike/motorbike rider's real running cost per mile is far below
        // a car or van's, so a flat car-based estimate would badly overstate
        // cost (and therefore understate value) for anyone not driving.
        // Falls back to the driver's current default vehicle for the rare
        // case no covering trip is found (e.g. very old data).
        let hitVehicle = store.trips.first { $0.startedAt <= date && $0.endedAt >= date }?.vehicle ?? store.settings.defaultVehicle
        let vehicleCostPerMile = hitVehicle.rateBand(on: date).first
        deliveryHits.append((weekday, band, hour, sorted[index].coordinate, date, isLocationTrustworthy, approachMeters, legMeters, vehicleCostPerMile))
        index = dropIndex + 1
      } else {
        index += 1
      }
    }

    let paidMiles = paidMeters / 1609.34 * roadFactor
    let totalMiles = max(totalMeters / 1609.34 * roadFactor, paidMiles)
    let deadMiles = max(0, totalMiles - paidMiles)
    let activeHours = activeSeconds / 3600

    // Per-weekday unpaid-miles % — same maths as the overall deadMilePct,
    // just scoped to one day, so the day breakdown can show its own figure
    // instead of the whole period's aggregate.
    func deadMilePct(forWeekday wd: Int) -> Int? {
      let paidMi = (paidMetersByWeekday[wd] ?? 0) / 1609.34 * roadFactor
      let totalMi = max((totalMetersByWeekday[wd] ?? 0) / 1609.34 * roadFactor, paidMi)
      guard totalMi > 0 else { return nil }
      return Int((max(0, totalMi - paidMi) / totalMi * 100).rounded())
    }

    // Busy-hours histogram across the whole period (every delivery by hour) —
    // powers the "when you're busy" chart on the Monthly/Yearly panels.
    var periodHourCounts = Array(repeating: 0, count: 24)
    for hit in deliveryHits where hit.hour >= 0 && hit.hour < 24 {
      periodHourCounts[hit.hour] += 1
    }

    // Rank every weekday + time-band bucket by delivery count.
    var counts: [String: Int] = [:]
    for hit in deliveryHits {
      counts["\(hit.weekday)|\(hit.band.rawValue)", default: 0] += 1
    }
    let ranked: [NativeShiftWindow] = counts
      .compactMap { key, count -> NativeShiftWindow? in
        let parts = key.split(separator: "|")
        guard parts.count == 2, let wd = Int(parts[0]), let band = NativeTimeFilter(rawValue: String(parts[1])) else { return nil }
        let share = deliveries > 0 ? Int((Double(count) / Double(deliveries) * 100).rounded()) : 0
        return NativeShiftWindow(weekday: wd, band: band, count: count, sharePct: share)
      }
      .sorted { $0.count > $1.count }
    let bestWindow = ranked.first?.label
    // The quietest bucket that still has a couple of data points — distinct
    // from the best one, so "avoid this" is a real, different recommendation.
    let quietWindow = ranked.count > 1 ? ranked.filter { $0.count >= 2 }.min { $0.count < $1.count } : nil

    // Cluster delivery start points into zones (~500m cells), tracking when each
    // area is busiest so "where to go" can carry a "when to go". deliveryHits
    // is already free of excluded places, since `sorted` was filtered above —
    // and further filtered to trustworthy locations only, so a shift with no
    // real classified stop never turns its own start/end point into a "zone".
    //
    // Each cell's weight blends three signals:
    //  - recency-weighted popularity (older deliveries count for less, so a
    //    closed restaurant or a changed local scene fades out on its own
    //    instead of being remembered forever)
    //  - dead-mile efficiency (how much unpaid repositioning it historically
    //    took to reach this zone — busiest isn't the same as most profitable,
    //    and this is the one signal only this app's mileage tracking can
    //    actually provide)
    //  - a food-POI density prior, which dominates while a zone has barely
    //    any real evidence and fades out as real deliveries accumulate — the
    //    same "trust real evidence once there's enough of it" bar already
    //    used for NativeExploreCandidate.isValidated (3 real visits)
    var cells: [String: (coordinate: CLLocationCoordinate2D, rawCount: Int, decayedCount: Double, hours: [Int: Int], approachMeters: Double, paidMeters: Double, estimatedCost: Double)] = [:]
    let cellSize = 0.006
    let recencyHalfLifeDays = 60.0
    let now = Date()
    for hit in deliveryHits where hit.isLocationTrustworthy {
      let key = "\(Int((hit.coordinate.latitude / cellSize).rounded())),\(Int((hit.coordinate.longitude / cellSize).rounded()))"
      var cell = cells[key] ?? (hit.coordinate, 0, 0, [:], 0, 0, 0)
      let ageDays = max(0, now.timeIntervalSince(hit.date) / 86_400)
      let decay = pow(0.5, ageDays / recencyHalfLifeDays)
      cell.rawCount += 1
      cell.decayedCount += decay
      cell.hours[hit.hour, default: 0] += 1
      cell.approachMeters += hit.approachMeters
      cell.paidMeters += hit.paidLegMeters
      // This hit's own actual vehicle cost — not a flat zone-wide rate — so a
      // day ridden on a bike doesn't get charged a car's running cost.
      let hitMiles = (hit.approachMeters + hit.paidLegMeters) / 1609.34 * roadFactor
      cell.estimatedCost += hitMiles * hit.vehicleCostPerMile
      cells[key] = cell
    }
    // Attribute each logged income record across the zone(s) actually worked
    // during its *own* period — the finest grain available, since income
    // isn't logged per delivery. A record's period isn't always a single
    // day: logging "Week" stores periodStart/periodEnd spanning that whole
    // Monday–Sunday (with `date` itself just the day the driver happened to
    // pick in the UI) — attributing by `date` alone would dump an entire
    // week's income onto one day and nothing onto the other six. Spreading
    // proportionally across every day *within* the record's actual period,
    // weighted by delivery count, handles Day and Week today and would
    // handle a Month period automatically too, if one's ever added, since
    // none of this hardcodes a specific period length. A record whose period
    // happens to only cover one zone is attributed exactly; one spanning
    // several zones is a proportional guess (split by delivery count), so
    // those count for less until enough of them accumulate. This is what
    // lets a zone with a lot of unpaid repositioning still rank well if the
    // deliveries it leads to are genuinely worth the detour, instead of just
    // penalising every unpaid mile the same regardless of payoff.
    struct NativeZoneIncomeAccumulator {
      var exactIncome: Double = 0
      var exactDeliveries: Int = 0
      var splitIncome: Double = 0
      var splitDeliveries: Int = 0
      // One entry per unambiguous record attributed to this zone — lets the
      // confidence check below tell "consistently decent" apart from "one
      // lucky record carrying the average", the same distinction
      // weekdayReliability already draws for day-of-week counts.
      var exactDayAmounts: [Double] = []
    }
    var incomeByCell: [String: NativeZoneIncomeAccumulator] = [:]
    let trustworthyHits = deliveryHits.filter(\.isLocationTrustworthy)
    let incomeRecords = store.records.filter { $0.kind == .income && ($0.amount ?? 0) > 0 }
    for record in incomeRecords {
      guard let amount = record.amount else { continue }
      let periodStart = Calendar.current.startOfDay(for: record.periodStart ?? record.date)
      let periodEnd = Calendar.current.startOfDay(for: record.periodEnd ?? record.date)
      let hitsInPeriod = trustworthyHits.filter { hit in
        let hitDay = Calendar.current.startOfDay(for: hit.date)
        return hitDay >= periodStart && hitDay <= periodEnd
      }
      guard !hitsInPeriod.isEmpty else { continue }
      let cellsInPeriod = Dictionary(grouping: hitsInPeriod) { hit in
        "\(Int((hit.coordinate.latitude / cellSize).rounded())),\(Int((hit.coordinate.longitude / cellSize).rounded()))"
      }
      let isExactPeriod = cellsInPeriod.count == 1
      for (key, hitsInCell) in cellsInPeriod {
        let share = Double(hitsInCell.count) / Double(hitsInPeriod.count)
        var acc = incomeByCell[key] ?? NativeZoneIncomeAccumulator()
        if isExactPeriod {
          acc.exactIncome += amount * share
          acc.exactDeliveries += hitsInCell.count
          acc.exactDayAmounts.append(amount)
        } else {
          acc.splitIncome += amount * share
          acc.splitDeliveries += hitsInCell.count
        }
        incomeByCell[key] = acc
      }
    }
    // Split-day attribution is a guess, so it counts for less than a day
    // that was unambiguous.
    let splitDayTrust = 0.4
    // Estimated cost is *subtracted* from income, not used as a divisor — an
    // early attempt divided attributed income by zone miles (£/mile), but
    // that quietly double-penalises a zone's unpaid roaming: once by not
    // being paid for it, and again by inflating the denominator it's divided
    // into. A short, cheap delivery paying £5 came out "more valuable per
    // mile" than a big £60 order that took a long detour to reach — exactly
    // backwards from "if the income's good enough, the detour was worth it".
    // Subtracting cell.estimatedCost (already vehicle-aware per delivery,
    // see above) instead means a big enough payout can straightforwardly
    // outweigh the roaming it took to earn it, and a zone that's a net loss
    // after estimated costs correctly still comes out negative rather than
    // just "a worse ratio".
    func netValuePerDelivery(for key: String, cell: (coordinate: CLLocationCoordinate2D, rawCount: Int, decayedCount: Double, hours: [Int: Int], approachMeters: Double, paidMeters: Double, estimatedCost: Double)) -> (value: Double, confidence: Double)? {
      guard let acc = incomeByCell[key] else { return nil }
      let effectiveIncome = acc.exactIncome + acc.splitIncome * splitDayTrust
      let effectiveDeliveries = Double(acc.exactDeliveries) + Double(acc.splitDeliveries) * splitDayTrust
      guard effectiveDeliveries > 0 else { return nil }
      let netValue = effectiveIncome - cell.estimatedCost
      let incomeConfidenceK = 4.0   // income evidence is scarcer than raw visit counts, so ask for a touch more of it
      // Is this zone consistently decent, or is one lucky day carrying the
      // whole average? Same coefficient-of-variation check as
      // weekdayReliability, just over this zone's own unambiguous days —
      // only ever dampens confidence, never boosts it, same restraint as
      // everywhere else this pattern is used.
      let consistencyFactor: Double = {
        guard acc.exactDayAmounts.count >= 3 else { return 1.0 }
        let mean = acc.exactDayAmounts.reduce(0, +) / Double(acc.exactDayAmounts.count)
        guard mean > 0 else { return 1.0 }
        let variance = acc.exactDayAmounts.reduce(0) { $0 + pow($1 - mean, 2) } / Double(acc.exactDayAmounts.count)
        let cv = sqrt(variance) / mean
        return cv > 1.0 ? 0.6 : 1.0
      }()
      let confidence = (effectiveDeliveries / (effectiveDeliveries + incomeConfidenceK)) * consistencyFactor
      return (netValue / effectiveDeliveries, confidence)
    }
    let allNetValues: [Double] = cells.compactMap { key, cell in netValuePerDelivery(for: key, cell: cell)?.value }
    // Net value can be negative (a zone that's a real loss once estimated
    // cost is factored in) — min-max scale rather than assume 0 is the floor.
    let minNetValue = allNetValues.min() ?? 0
    let maxNetValue = allNetValues.max() ?? 0
    let netValueRange = maxNetValue - minNetValue

    let maxDecayedCount = cells.values.map(\.decayedCount).max() ?? 1
    let zoneConfidenceK = 3.0   // matches NativeExploreCandidate.isValidated's "3 real visits" bar
    // Has "your best zone" actually been paying off in practice? Blends two
    // kinds of evidence — inferred from logged income, and direct "was this
    // worth it?" taps — and only ever dampens the final weight, same
    // restraint as peakHitRate: a good hit rate never inflates a zone beyond
    // what it already earned, it just stops confidently pointing somewhere
    // that keeps not paying off.
    let incomeHitRate = NativeZoneOutcomeTracker.shared.zoneHitRate
    let explicitHitRate = NativeZoneOutcomeTracker.shared.explicitHitRate
    let combinedZoneHitRate: Double? = {
      switch (incomeHitRate, explicitHitRate) {
      case let (income?, explicit?): return (income + explicit) / 2
      case let (income?, nil): return income
      case let (nil, explicit?): return explicit
      default: return nil
      }
    }()
    let zoneConfidenceFactor: Double = {
      guard let combinedZoneHitRate else { return 1.0 }
      if combinedZoneHitRate < 0.35 { return 0.5 }
      if combinedZoneHitRate < 0.5 { return 0.75 }
      return 1.0
    }()
    let zones = cells.map { key, cell -> NativeZonePoint in
      let peak = cell.hours.max { $0.value < $1.value }?.key
      let popularity = cell.decayedCount / maxDecayedCount
      let totalCellMeters = cell.approachMeters + cell.paidMeters
      let deadMilePct = totalCellMeters > 0 ? Int((cell.approachMeters / totalCellMeters * 100).rounded()) : nil
      // No approach-leg data for this cell yet → stay neutral rather than
      // silently reward or punish it in the blend below.
      let efficiency = deadMilePct.map { 1 - Double($0) / 100 } ?? 0.5
      // "Was the roaming worth it" is best answered by what a zone actually
      // nets (income minus an estimated cost for the miles it took), not
      // just how many miles it cost — so real attributed net value is the
      // primary value signal once there's enough of it, falling back to the
      // dead-mile-based efficiency guess while there isn't.
      let incomeResult = netValuePerDelivery(for: key, cell: cell)
      let valueSignal: Double
      if let incomeResult {
        let normalizedNetValue = netValueRange > 0 ? (incomeResult.value - minNetValue) / netValueRange : 0.5
        valueSignal = incomeResult.confidence * normalizedNetValue + (1 - incomeResult.confidence) * efficiency
      } else {
        valueSignal = efficiency
      }
      let realSignal = popularity * 0.55 + valueSignal * 0.45
      // Fall back to the real signal itself while the async POI lookup is
      // still resolving, so a zone isn't held back just because the prior
      // hasn't loaded yet.
      let poiPrior = NativeZonePOIPrior.shared.priorScore(for: cell.coordinate) ?? realSignal
      let confidence = Double(cell.rawCount) / (Double(cell.rawCount) + zoneConfidenceK)
      let weight = (confidence * realSignal + (1 - confidence) * poiPrior) * zoneConfidenceFactor
      return NativeZonePoint(coordinate: cell.coordinate, weight: weight, count: cell.rawCount, peakHour: peak, deadMilePct: deadMilePct)
    }

    // £/hr over the last 14 days: logged income ÷ active hours in the window.
    let windowStart = Date().addingTimeInterval(-14 * 86_400)
    let income = store.records
      .filter { $0.kind == .income && $0.date >= windowStart }
      .reduce(0.0) { $0 + ($1.amount ?? 0) }
    let recentActive = recentActiveHours(sorted, since: windowStart, shiftGap: shiftGap)
    // Only surface a rate we can stand behind. Passive hour-detection can be thin
    // (a couple of short shifts), which inflates £/hr into nonsense — when the
    // result lands outside a believable gig-delivery range, stay quiet rather than
    // show a number that undermines trust.
    let rawPerHour = (income > 0 && recentActive > 1) ? income / recentActive : nil
    let perHour: Double? = rawPerHour.flatMap { (4...45).contains($0) ? $0 : nil }

    let prevWindowStart = windowStart.addingTimeInterval(-14 * 86_400)

    // Platform mix: a real, cross-platform ranking no single delivery app can
    // offer — every platform's real, logged share of this period's income,
    // and how each has shifted. Only worth showing once there's an actual mix
    // (2+ platforms) — a single platform logged isn't a "mix" insight.
    let currentPlatformIncome = store.records.filter { $0.kind == .income && $0.date >= windowStart }
    let previousPlatformIncome = store.records.filter { $0.kind == .income && $0.date >= prevWindowStart && $0.date < windowStart }
    func platformTotals(_ records: [NativeRecord]) -> [String: Double] {
      var totals: [String: Double] = [:]
      for r in records { totals[r.platform ?? "Other", default: 0] += r.amount ?? 0 }
      return totals
    }
    let currentTotals = platformTotals(currentPlatformIncome)
    let previousTotals = platformTotals(previousPlatformIncome)
    let currentSum = currentTotals.values.reduce(0, +)
    let previousSum = previousTotals.values.reduce(0, +)
    var platformShares: [NativePlatformShare] = []
    if currentSum > 0, currentTotals.count >= 2 {
      for (platform, amount) in currentTotals.sorted(by: { $0.value > $1.value }) {
        let sharePct = Int((amount / currentSum * 100).rounded())
        var deltaPct: Int? = nil
        if previousSum > 0, let prevAmount = previousTotals[platform] {
          let prevSharePct = Int((prevAmount / previousSum * 100).rounded())
          let delta = sharePct - prevSharePct
          if abs(delta) >= 8 { deltaPct = delta }
        }
        platformShares.append(NativePlatformShare(platform: platform, sharePct: sharePct, deltaPct: deltaPct))
      }
    }

    // Reliability: does this weekday look the same week to week, or is one
    // outlier week doing all the work? The per-day counterpart to the
    // consistency check already folded into overall confidence.
    var weekByWeekday: [Int: [Date: Int]] = [:]
    for hit in deliveryHits {
      guard let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: hit.date)?.start else { continue }
      weekByWeekday[hit.weekday, default: [:]][weekStart, default: 0] += 1
    }
    var weekdayReliability: [Int: NativeDayReliability] = [:]
    for (wd, weeks) in weekByWeekday {
      let counts = weeks.values.map(Double.init)
      guard counts.count >= 3 else { continue }   // need a few distinct weeks to say anything
      let mean = counts.reduce(0, +) / Double(counts.count)
      guard mean > 0 else { continue }
      let variance = counts.reduce(0) { $0 + pow($1 - mean, 2) } / Double(counts.count)
      let cv = sqrt(variance) / mean
      if cv <= 0.6 { weekdayReliability[wd] = .reliable }
      else if cv > 1.0 { weekdayReliability[wd] = .erratic }
    }

    // Weekly overview: how deliveries split across the seven weekdays.
    var weekdayCounts: [Int: Int] = [:]
    for hit in deliveryHits { weekdayCounts[hit.weekday, default: 0] += 1 }
    let weekdayStats = (0...6).map { wd -> NativeWeekdayStat in
      let count = weekdayCounts[wd] ?? 0
      let share = deliveries > 0 ? Int((Double(count) / Double(deliveries) * 100).rounded()) : 0
      return NativeWeekdayStat(weekday: wd, count: count, sharePct: share)
    }

    // Per-weekday best band + zone (busiest first) — the "when & where" list.
    let weekdayDetails: [NativeWeekdayDetail] = (0...6)
      .filter { (weekdayCounts[$0] ?? 0) > 0 }
      .map { wd -> NativeWeekdayDetail in
        let (band, zone) = bestBandAndZone(for: wd, deliveryHits: deliveryHits, cellSize: cellSize)
        return NativeWeekdayDetail(weekday: wd, band: band, count: weekdayCounts[wd] ?? 0, coordinate: zone,
                                    deadMilePct: deadMilePct(forWeekday: wd))
      }
      .sorted { $0.count > $1.count }

    // Today's plan: today if it has data, otherwise the next weekday (working
    // day or not — we only ever have data on working days anyway) that does.
    let todayWeekday = Calendar.current.component(.weekday, from: Date()) - 1
    let planWeekday = (0..<7)
      .map { (todayWeekday + $0) % 7 }
      .first { weekdayCounts[$0, default: 0] > 0 }
    let todayPlan: NativeDayPlan? = planWeekday.map { wd in
      let (bestBand, topZone) = bestBandAndZone(for: wd, deliveryHits: deliveryHits, cellSize: cellSize)

      // Hour-level shape for that weekday → concrete drive/break windows.
      var hourCounts = Array(repeating: 0, count: 24)
      for hit in deliveryHits where hit.weekday == wd { hourCounts[hit.hour] += 1 }
      let drives = nativeHourWindows(from: hourCounts)
      let breakWin = nativeBreakWindow(from: drives)

      var bandCounts: [NativeTimeFilter: Int] = [:]
      for hit in deliveryHits where hit.weekday == wd { bandCounts[hit.band, default: 0] += 1 }
      let order: [NativeTimeFilter] = [.morning, .lunch, .afternoon, .dinner, .late]
      let breakBand = order
        .filter { $0 != bestBand && (bandCounts[$0] ?? 0) >= 1 }
        .min { (bandCounts[$0] ?? 0) < (bandCounts[$1] ?? 0) }

      return NativeDayPlan(
        weekday: wd,
        isToday: wd == todayWeekday,
        deliveries: weekdayCounts[wd] ?? 0,
        bestBand: bestBand,
        breakBand: breakBand,
        zone: topZone,
        hourCounts: hourCounts,
        driveWindows: drives,
        breakWindow: breakWin
      )
    }

    let lastShift = debrief(sorted: sorted, deliveryHits: deliveryHits, store: store, shiftGap: shiftGap, cellSize: cellSize)
    let activeDays = Set(sorted.map { Calendar.current.startOfDay(for: $0.arrival) }).count
    let daySpan = Calendar.current.dateComponents(
      [.day],
      from: Calendar.current.startOfDay(for: sorted[0].arrival),
      to: Calendar.current.startOfDay(for: sorted[sorted.count - 1].arrival)
    ).day ?? 0

    return NativeShiftInsights(
      deliveries: deliveries,
      activeHours: activeHours,
      paidMiles: paidMiles,
      deadMiles: deadMiles,
      bestWindow: bestWindow,
      perHour: perHour,
      windows: Array(ranked.prefix(5)),
      quietWindow: quietWindow,
      zones: zones,
      weekdayStats: weekdayStats,
      weekdayDetails: weekdayDetails,
      todayPlan: todayPlan,
      lastShift: lastShift,
      activeDays: activeDays,
      daySpan: daySpan,
      peakHitRate: NativeOutcomeTracker.shared.peakHitRate,
      weekdayReliability: weekdayReliability,
      platformShares: platformShares,
      hourCounts: periodHourCounts
    )
  }

  /// Read on the most recent day (in the last fortnight) that has both stops
  /// and logged income: that day's £/hr vs your usual for that weekday, and
  /// whether you finished before your typical peak band.
  @MainActor
  private static func debrief(sorted: [NativeVisit], deliveryHits: [NativeDeliveryHit], store: OkkleStore, shiftGap: TimeInterval, cellSize: Double) -> NativeShiftDebrief? {
    let cal = Calendar.current
    // Income by calendar day (last 14 days).
    let since = Date().addingTimeInterval(-14 * 86_400)
    var incomeByDay: [Date: Double] = [:]
    for r in store.records where r.kind == .income && r.date >= since {
      incomeByDay[cal.startOfDay(for: r.date), default: 0] += r.amount ?? 0
    }
    guard !incomeByDay.isEmpty else { return nil }

    // The most recent day that also has tracked stops.
    let daysWithStops = Set(sorted.map { cal.startOfDay(for: $0.arrival) })
    guard let day = incomeByDay.keys.filter({ daysWithStops.contains($0) }).max() else { return nil }

    let dayVisits = sorted.filter { cal.isDate($0.arrival, inSameDayAs: day) }
    let activeHours = recentActiveHours(dayVisits, since: day, shiftGap: shiftGap)
    guard activeHours > 0.25, let income = incomeByDay[day], income > 0 else { return nil }
    let perHour = income / activeHours
    let weekday = cal.component(.weekday, from: day) - 1

    // Average £/hr for that weekday across the fortnight.
    var wdIncome = 0.0
    for (d, inc) in incomeByDay where cal.component(.weekday, from: d) - 1 == weekday { wdIncome += inc }
    var wdHours = 0.0
    let grouped = Dictionary(grouping: sorted.filter { cal.component(.weekday, from: $0.arrival) - 1 == weekday }) { cal.startOfDay(for: $0.arrival) }
    for (d, vs) in grouped { wdHours += recentActiveHours(vs, since: d, shiftGap: shiftGap) }
    let weekdayAvg: Double? = wdHours > 0.25 ? wdIncome / wdHours : nil

    // Did they finish before their usual peak band for that weekday?
    let (peakBand, _) = bestBandAndZone(for: weekday, deliveryHits: deliveryHits, cellSize: cellSize)
    let lastHour = dayVisits.map { cal.component(.hour, from: $0.arrival) }.max() ?? 0
    let peakStart = peakBand.startHour
    let finishedBeforePeak = peakStart != nil && lastHour < (peakStart ?? 0)

    return NativeShiftDebrief(
      weekday: weekday,
      perHour: perHour,
      weekdayAvgPerHour: weekdayAvg,
      finishedBeforePeak: finishedBeforePeak,
      peakLabel: peakBand.label
    )
  }

  /// Real driven distance between two timestamps, normalised back to the
  /// straight-line-equivalent metres this builder stores internally. The caller
  /// applies the shared road factor once when converting aggregate metres to
  /// miles; normalising here prevents real GPS/trip mileage being inflated by
  /// that factor a second time. Falls back to nil when no trip data covers the
  /// window so callers can still use a straight-line estimate.
  private static func routeMeters(from start: Date, to end: Date, trips: [NativeTrip]) -> Double? {
    guard end > start else { return nil }
    var total = 0.0
    var sawSegment = false
    for trip in trips {
      guard trip.startedAt < end, trip.endedAt > start else { continue }
      let inWindow = trip.points.filter { point in
        guard let t = point.timestamp else { return false }
        return t >= start && t <= end
      }
      if inWindow.count <= 1 {
        let startDelta = abs(trip.startedAt.timeIntervalSince(start))
        let endDelta = abs(trip.endedAt.timeIntervalSince(end))
        if startDelta <= 120, endDelta <= 120, trip.miles > 0 {
          total += trip.miles * 1609.34 / routeDistanceNormalizationFactor
          sawSegment = true
        }
        continue
      }
      sawSegment = true
      for i in 1..<inWindow.count {
        let a = CLLocation(latitude: inWindow[i - 1].latitude, longitude: inWindow[i - 1].longitude)
        let b = CLLocation(latitude: inWindow[i].latitude, longitude: inWindow[i].longitude)
        total += b.distance(from: a) / routeDistanceNormalizationFactor
      }
    }
    return sawSegment ? total : nil
  }

  private static func recentActiveHours(_ sorted: [NativeVisit], since: Date, shiftGap: TimeInterval) -> Double {
    var seconds = 0.0
    for k in 1..<max(sorted.count, 1) {
      let prev = sorted[k - 1], cur = sorted[k]
      guard cur.arrival >= since else { continue }
      let gap = cur.arrival.timeIntervalSince(prev.departure)
      if gap < shiftGap { seconds += max(0, gap) + prev.dwell }
    }
    return seconds / 3600
  }
}

typealias NativeDeliveryHit = (weekday: Int, band: NativeTimeFilter, hour: Int, coordinate: CLLocationCoordinate2D, date: Date, isLocationTrustworthy: Bool, approachMeters: Double, paidLegMeters: Double, vehicleCostPerMile: Double)

/// The busiest time-band and roughly-where for one weekday.
func bestBandAndZone(for weekday: Int, deliveryHits: [NativeDeliveryHit], cellSize: Double) -> (band: NativeTimeFilter, zone: CLLocationCoordinate2D?) {
  var bandCounts: [NativeTimeFilter: Int] = [:]
  var cells: [String: (coordinate: CLLocationCoordinate2D, count: Int)] = [:]
  for hit in deliveryHits where hit.weekday == weekday {
    bandCounts[hit.band, default: 0] += 1
    guard hit.isLocationTrustworthy else { continue }
    let key = "\(Int((hit.coordinate.latitude / cellSize).rounded())),\(Int((hit.coordinate.longitude / cellSize).rounded()))"
    if let existing = cells[key] {
      cells[key] = (existing.coordinate, existing.count + 1)
    } else {
      cells[key] = (hit.coordinate, 1)
    }
  }
  let band = bandCounts.max { $0.value < $1.value }?.key ?? .afternoon
  let zone = cells.values.max { $0.count < $1.count }?.coordinate
  return (band, zone)
}

/// Contiguous runs of "busy" hours (≥ 40% of the day's peak), each a drive window.
func nativeHourWindows(from hourCounts: [Int]) -> [NativeHourWindow] {
  let peak = hourCounts.max() ?? 0
  guard peak > 0 else { return [] }
  let threshold = max(1, Int((Double(peak) * 0.4).rounded(.up)))
  var windows: [NativeHourWindow] = []
  var start: Int?
  var runCount = 0
  for h in 0..<24 {
    if hourCounts[h] >= threshold {
      if start == nil { start = h; runCount = 0 }
      runCount += hourCounts[h]
    } else if let s = start {
      windows.append(NativeHourWindow(startHour: s, endHour: h - 1, count: runCount))
      start = nil
    }
  }
  if let s = start { windows.append(NativeHourWindow(startHour: s, endHour: 23, count: runCount)) }
  return windows
}

/// The widest quiet gap between two drive windows — the natural break.
func nativeBreakWindow(from drives: [NativeHourWindow]) -> NativeHourWindow? {
  guard drives.count >= 2 else { return nil }
  var best: NativeHourWindow?
  for i in 1..<drives.count {
    let gapStart = drives[i - 1].endHour + 1
    let gapEnd = drives[i].startHour - 1
    guard gapEnd >= gapStart else { continue }
    let length = gapEnd - gapStart + 1
    if best == nil || length > (best!.endHour - best!.startHour + 1) {
      best = NativeHourWindow(startHour: gapStart, endHour: gapEnd, count: 0)
    }
  }
  return best
}
