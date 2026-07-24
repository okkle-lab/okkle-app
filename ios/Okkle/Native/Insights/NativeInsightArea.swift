import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class NativeOneShotLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
  static let shared = NativeOneShotLocator()
  @Published private(set) var coordinate: CLLocationCoordinate2D?
  private let manager = CLLocationManager()

  override init() {
    super.init()
    manager.delegate = self
  }

  func request() {
    guard coordinate == nil else { return }
    let status = manager.authorizationStatus
    guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
    manager.requestLocation()
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    Task { @MainActor in self.coordinate = location.coordinate }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Self-correcting confidence — checks the model's own predictions
// against what actually got logged, entirely silently.

/// One logged pay entry, tagged with whether the model had called its date a
/// "peak" day at the moment it was logged.
struct NativeOutcomeSample: Codable, Equatable {
  let date: Date
  let period: NativePayPeriod
  let amount: Double
  let wasPredictedPeakDay: Bool
}

/// Tracks whether "your peak" has actually been paying off. Confidence
/// shouldn't just mean "I have a lot of data" — it should mean "and I've
/// been right." Every time pay gets logged, this checks: was that date one
/// the model called a peak, and did it come in at or above what the driver
/// normally logs for that same period length (day vs week)? Only ever used to
/// *cap* confidence when the hit rate is poor — a good hit rate never boosts
/// confidence beyond what the sample size/consistency already earned, to stay
/// on the conservative side.
@MainActor
final class NativeOutcomeTracker: ObservableObject {
  static let shared = NativeOutcomeTracker()

  var samples: [NativeOutcomeSample] { OkkleStore.shared.insightEvidence.outcomeSamples }

  func record(amount: Double, period: NativePayPeriod, wasPredictedPeakDay: Bool) {
    guard amount > 0 else { return }
    OkkleStore.shared.updateInsightEvidence { evidence in
      evidence.outcomeSamples.append(NativeOutcomeSample(
        date: Date(),
        period: period,
        amount: amount,
        wasPredictedPeakDay: wasPredictedPeakDay
      ))
      if evidence.outcomeSamples.count > 40 {
        evidence.outcomeSamples.removeFirst(evidence.outcomeSamples.count - 40)
      }
    }
    objectWillChange.send()
  }

  /// Of the times the model called a period "your peak", how often did the
  /// logged pay for it actually beat the driver's own typical amount for that
  /// same period length? Compares like-for-like (day logs against day logs,
  /// week logs against week logs) since the two scale very differently. Stays
  /// nil until there's enough evidence either way to say something honest.
  var peakHitRate: Double? {
    let peakSamples = samples.filter(\.wasPredictedPeakDay)
    guard peakSamples.count >= 5 else { return nil }
    var hits = 0
    var evaluated = 0
    for sample in peakSamples {
      let sameScale = samples.filter { $0.period == sample.period }.map(\.amount).sorted()
      guard sameScale.count >= 3 else { continue }
      let median = sameScale[sameScale.count / 2]
      evaluated += 1
      if sample.amount >= median { hits += 1 }
    }
    guard evaluated >= 5 else { return nil }
    return Double(hits) / Double(evaluated)
  }

}

/// One logged pay entry, tagged with whether that day's work actually
/// happened near the zone the model was recommending at the time.
struct NativeZoneOutcomeSample: Codable, Equatable {
  let date: Date
  let period: NativePayPeriod
  let amount: Double
  let wasNearRecommendedZone: Bool
}

/// The zone-ranking counterpart to NativeOutcomeTracker: closes the loop on
/// "where to go" the same way that one already closes the loop on "when to
/// go". Every time pay gets logged, checks whether that day's work happened
/// near that weekday's recommended zone, and whether the pay came in at or
/// above what the driver normally logs for that period length. Only ever
/// used to *dampen* zone weights when the hit rate is poor — same restraint
/// as peakHitRate, a good hit rate never inflates a zone's weight beyond
/// what its own popularity/efficiency/POI signal already earned.
@MainActor
final class NativeZoneOutcomeTracker: ObservableObject {
  static let shared = NativeZoneOutcomeTracker()

  var samples: [NativeZoneOutcomeSample] { OkkleStore.shared.insightEvidence.zoneOutcomeSamples }

  func record(amount: Double, period: NativePayPeriod, wasNearRecommendedZone: Bool) {
    guard amount > 0 else { return }
    OkkleStore.shared.updateInsightEvidence { evidence in
      evidence.zoneOutcomeSamples.append(NativeZoneOutcomeSample(
        date: Date(),
        period: period,
        amount: amount,
        wasNearRecommendedZone: wasNearRecommendedZone
      ))
      if evidence.zoneOutcomeSamples.count > 40 {
        evidence.zoneOutcomeSamples.removeFirst(evidence.zoneOutcomeSamples.count - 40)
      }
    }
    objectWillChange.send()
  }

  var zoneHitRate: Double? {
    let nearSamples = samples.filter(\.wasNearRecommendedZone)
    guard nearSamples.count >= 5 else { return nil }
    var hits = 0
    var evaluated = 0
    for sample in nearSamples {
      let sameScale = samples.filter { $0.period == sample.period }.map(\.amount).sorted()
      guard sameScale.count >= 3 else { continue }
      let median = sameScale[sameScale.count / 2]
      evaluated += 1
      if sample.amount >= median { hits += 1 }
    }
    guard evaluated >= 5 else { return nil }
    return Double(hits) / Double(evaluated)
  }

  // MARK: - Explicit feedback ("was this worth it?")
  //
  // A direct yes/no tap after a shift is simpler and more reliable ground
  // truth than inferring from logged income (income can be moved by traffic,
  // weather, luck) — tracked as its own tally rather than folded into the
  // income-comparison samples above, which need real £ amounts to stay
  // meaningful.
  var explicitPositive: Int { OkkleStore.shared.insightEvidence.explicitPositive }
  var explicitNegative: Int { OkkleStore.shared.insightEvidence.explicitNegative }

  var explicitHitRate: Double? {
    let total = explicitPositive + explicitNegative
    guard total >= 3 else { return nil }
    return Double(explicitPositive) / Double(total)
  }

  func recordExplicitFeedback(wasWorthIt: Bool) {
    OkkleStore.shared.updateInsightEvidence { evidence in
      if wasWorthIt {
        evidence.explicitPositive += 1
      } else {
        evidence.explicitNegative += 1
      }
    }
    objectWillChange.send()
  }
}

// MARK: - Areas to try — cold-start guesses, clearly labelled as guesses.
//
// There's no order-volume data to learn real demand from on day one, so any
// "try this area" guess is a guess — surfaced as exactly that (see
// bestUnvalidatedCandidate below) rather than with the same confidence as an
// earned recommendation. This layer scores nearby candidates by restaurant
// density, then watches real passive visits: if the driver ever naturally
// drives near a candidate, that visit's day becomes a trial. Enough trials
// with decent earnings and the candidate is "validated" — at which point
// it's simply real data, already flowing into the normal zone/ranking
// pipeline like anywhere else the driver has worked. That's the automatic
// feedback loop: no manual promotion, no dashboard, just evidence
// accumulating quietly until a guess earns its way into being real.

/// One candidate the background layer discovered — persisted so trial
/// evidence survives across launches.
/// A single restaurant within range isn't "restaurant-dense" — it's one
/// venue that happens to sit inside whatever's actually there (a business
/// park, a housing estate). Below this many nearby food POIs, a candidate
/// isn't worth surfacing as a delivery-area guess at all, even if it's the
/// least-bad of a weak batch. Applied both when a candidate is first
/// discovered and again when picking which one to show, so a legacy
/// candidate saved before this threshold existed doesn't linger either.
let nativeMinimumViableAreaPoiScore = 3

struct NativeExploreCandidate: Codable, Identifiable, Equatable {
  var id = UUID()
  let name: String
  let latitude: Double
  let longitude: Double
  let poiScore: Int
  let discoveredAt: Date
  var timesNearby: Int = 0
  var trialDays: Int = 0
  var totalDayIncome: Double = 0

  var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
  /// A handful of real visits nearby and this isn't a guess any more — it's
  /// backed by the driver's own history, same as any other zone.
  var isValidated: Bool { timesNearby >= 3 }
}

/// All learned Insights state lives beside the user's records and trips, so it
/// participates in backup, reset and iCloud merge as one versioned unit.
struct NativeInsightEvidence: Codable, Equatable {
  static let currentVersion = 1

  var version = currentVersion
  var outcomeSamples: [NativeOutcomeSample] = []
  var zoneOutcomeSamples: [NativeZoneOutcomeSample] = []
  var explicitPositive = 0
  var explicitNegative = 0
  var candidates: [NativeExploreCandidate] = []
  var fetchedAreaKeys: [String: Date] = [:]
  var poiPriorScores: [String: Double] = [:]
  var updatedAt: Date? = nil

  var isEmpty: Bool {
    outcomeSamples.isEmpty && zoneOutcomeSamples.isEmpty &&
      explicitPositive == 0 && explicitNegative == 0 && candidates.isEmpty &&
      fetchedAreaKeys.isEmpty && poiPriorScores.isEmpty
  }

  static func migratedFromLegacyDefaults(_ defaults: UserDefaults = .standard) -> NativeInsightEvidence? {
    let decoder = JSONDecoder()
    var evidence = NativeInsightEvidence()
    if let data = defaults.data(forKey: "uk.okkle.native.outcome.samples.v1"),
       let samples = try? decoder.decode([NativeOutcomeSample].self, from: data) {
      evidence.outcomeSamples = samples
    }
    if let data = defaults.data(forKey: "uk.okkle.native.zoneoutcome.samples.v1"),
       let samples = try? decoder.decode([NativeZoneOutcomeSample].self, from: data) {
      evidence.zoneOutcomeSamples = samples
    }
    if let data = defaults.data(forKey: "uk.okkle.native.zoneoutcome.explicit.v1"),
       let values = try? decoder.decode([Int].self, from: data), values.count == 2 {
      evidence.explicitPositive = values[0]
      evidence.explicitNegative = values[1]
    }
    if let data = defaults.data(forKey: "uk.okkle.native.explore.candidates.v1"),
       let candidates = try? decoder.decode([NativeExploreCandidate].self, from: data) {
      evidence.candidates = candidates
    }
    if let data = defaults.data(forKey: "uk.okkle.native.explore.fetchedKeys.v1"),
       let keys = try? decoder.decode([String: Date].self, from: data) {
      evidence.fetchedAreaKeys = keys
    }
    guard !evidence.isEmpty else { return nil }
    evidence.updatedAt = Date()
    return evidence
  }

  static func merged(_ lhs: NativeInsightEvidence, _ rhs: NativeInsightEvidence) -> NativeInsightEvidence {
    func outcomeKey(_ sample: NativeOutcomeSample) -> String {
      "\(sample.date.timeIntervalSinceReferenceDate)|\(sample.period.rawValue)|\(sample.amount)|\(sample.wasPredictedPeakDay)"
    }
    func zoneKey(_ sample: NativeZoneOutcomeSample) -> String {
      "\(sample.date.timeIntervalSinceReferenceDate)|\(sample.period.rawValue)|\(sample.amount)|\(sample.wasNearRecommendedZone)"
    }

    var merged = (rhs.updatedAt ?? .distantPast) > (lhs.updatedAt ?? .distantPast) ? rhs : lhs
    merged.version = currentVersion
    var uniqueOutcomes: [String: NativeOutcomeSample] = [:]
    for sample in lhs.outcomeSamples + rhs.outcomeSamples { uniqueOutcomes[outcomeKey(sample)] = sample }
    merged.outcomeSamples = uniqueOutcomes.values.sorted { $0.date < $1.date }.suffix(40).map { $0 }
    var uniqueZoneOutcomes: [String: NativeZoneOutcomeSample] = [:]
    for sample in lhs.zoneOutcomeSamples + rhs.zoneOutcomeSamples { uniqueZoneOutcomes[zoneKey(sample)] = sample }
    merged.zoneOutcomeSamples = uniqueZoneOutcomes.values.sorted { $0.date < $1.date }.suffix(40).map { $0 }
    merged.explicitPositive = max(lhs.explicitPositive, rhs.explicitPositive)
    merged.explicitNegative = max(lhs.explicitNegative, rhs.explicitNegative)
    merged.candidates = mergeCandidates(lhs.candidates, rhs.candidates)
    merged.fetchedAreaKeys = lhs.fetchedAreaKeys.merging(rhs.fetchedAreaKeys, uniquingKeysWith: max)
    merged.poiPriorScores = lhs.poiPriorScores.merging(rhs.poiPriorScores) { _, remote in remote }
    merged.updatedAt = [lhs.updatedAt, rhs.updatedAt].compactMap { $0 }.max()
    return merged
  }

  private static func mergeCandidates(
    _ lhs: [NativeExploreCandidate],
    _ rhs: [NativeExploreCandidate]
  ) -> [NativeExploreCandidate] {
    var candidates = Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) })
    for candidate in rhs {
      if let current = candidates[candidate.id] {
        var combined = candidate.discoveredAt >= current.discoveredAt ? candidate : current
        combined.timesNearby = max(current.timesNearby, candidate.timesNearby)
        combined.trialDays = max(current.trialDays, candidate.trialDays)
        combined.totalDayIncome = max(current.totalDayIncome, candidate.totalDayIncome)
        candidates[candidate.id] = combined
      } else {
        candidates[candidate.id] = candidate
      }
    }
    return Array(candidates.values).sorted { $0.discoveredAt < $1.discoveredAt }.suffix(30).map { $0 }
  }
}

@MainActor
final class NativeExploreCandidateStore: ObservableObject {
  static let shared = NativeExploreCandidateStore()

  var candidates: [NativeExploreCandidate] { OkkleStore.shared.insightEvidence.candidates }

  /// Add newly discovered candidates, keeping any trial evidence already
  /// collected for ones we're already tracking (matched by name *and*
  /// proximity — common UK street/area names like "High Street" repeat
  /// across many towns, so a name match alone would permanently suppress a
  /// genuinely new candidate just because a same-named one exists elsewhere).
  func merge(_ discovered: [(name: String, coordinate: CLLocationCoordinate2D, poiScore: Int)]) {
    var candidates = candidates
    for area in discovered {
      let newLocation = CLLocation(latitude: area.coordinate.latitude, longitude: area.coordinate.longitude)
      let alreadyKnown = candidates.contains { existing in
        guard existing.name.caseInsensitiveCompare(area.name) == .orderedSame else { return false }
        let existingLocation = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
        return existingLocation.distance(from: newLocation) < 2_000
      }
      guard !alreadyKnown else { continue }
      candidates.append(NativeExploreCandidate(name: area.name, latitude: area.coordinate.latitude,
                                               longitude: area.coordinate.longitude, poiScore: area.poiScore,
                                               discoveredAt: Date()))
    }
    trim(&candidates)
    OkkleStore.shared.updateInsightEvidence { $0.candidates = candidates }
    objectWillChange.send()
  }

  /// The strongest guess still unproven — what the cold-start card shows,
  /// clearly hedged, while the driver has no earned zones of their own yet.
  /// Once something validates it stops being a "candidate" at all (it's just
  /// a real zone now), so this naturally empties out as real data arrives.
  /// Requires a real cluster of food POIs, not just one — a lone pub inside
  /// an industrial estate shouldn't out-rank "nothing to suggest yet". Also
  /// excludes borough-level names directly (not just at discovery time) —
  /// candidates already saved before that fix existed would otherwise keep
  /// showing "Wandsworth" forever, since merge() only ever adds new
  /// candidates and never re-checks ones already stored.
  var bestUnvalidatedCandidate: NativeExploreCandidate? {
    candidates
      .filter {
        !$0.isValidated
          && $0.poiScore >= nativeMinimumViableAreaPoiScore
          && !nativeLondonBoroughNames.contains($0.name.lowercased())
      }
      .max { $0.poiScore < $1.poiScore }
  }

  /// Called on every real passive visit — the feedback half of the loop. If
  /// the visit lands near a candidate we're quietly testing, log a trial.
  func recordVisit(_ coordinate: CLLocationCoordinate2D, dayIncome: Double?) {
    var candidates = candidates
    guard !candidates.isEmpty else { return }
    let visitLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    var changed = false
    for i in candidates.indices {
      let cLoc = CLLocation(latitude: candidates[i].latitude, longitude: candidates[i].longitude)
      guard visitLoc.distance(from: cLoc) < 400 else { continue }
      candidates[i].timesNearby += 1
      if let dayIncome { candidates[i].totalDayIncome += dayIncome; candidates[i].trialDays += 1 }
      changed = true
    }
    if changed {
      OkkleStore.shared.updateInsightEvidence { $0.candidates = candidates }
      objectWillChange.send()
    }
  }

  private func trim(_ candidates: inout [NativeExploreCandidate]) {
    // A lightweight exploration log, not a growing database: drop anything
    // that's sat untouched for 90 days, and cap the total tracked.
    let cutoff = Date().addingTimeInterval(-90 * 86_400)
    candidates.removeAll { $0.discoveredAt < cutoff && $0.timesNearby == 0 }
    if candidates.count > 30 { candidates = Array(candidates.suffix(30)) }
  }

}

/// Move a coordinate `distanceKm` along `bearingDeg` (0 = north, clockwise) —
/// used to lay out a ring of candidate points around the driver.
func nativeOffsetCoordinate(_ origin: CLLocationCoordinate2D, distanceKm: Double, bearingDeg: Double) -> CLLocationCoordinate2D {
  let earthRadiusKm = 6371.0
  let bearing = bearingDeg * .pi / 180
  let lat1 = origin.latitude * .pi / 180
  let lon1 = origin.longitude * .pi / 180
  let angular = distanceKm / earthRadiusKm
  let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
  let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
  return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
}

/// Discovers nearby candidates and hands them to `NativeExploreCandidateStore`.
/// Runs silently — nothing here is ever rendered.
enum NativeAreaSuggester {
  private static var fetching = false
  // Persisted (not just in-memory) so relaunching the app or bouncing
  // between two working areas doesn't re-trigger the ~48-request
  // MapKit/Overpass scan for a cell that was already scanned recently.
  private static let fetchedKeyCooldown: TimeInterval = 24 * 60 * 60

  /// Lay out three rings of candidates (1.2km, 2.5km, and 4km out) around
  /// the driver, score them by restaurant density, and hand the top three
  /// to the store — excluding anywhere that resolves to a name the driver
  /// already knows. Streets can run for over a kilometre, so excluding by
  /// *name* (not raw distance) is what stops re-suggesting a street the
  /// driver already partly works.
  ///
  /// A single ring at a fixed distance/bearing set is a coarse sample — it's
  /// easy for every point to land on a quiet back road or a park even when
  /// a busy high street sits just a few hundred metres off one of them, or
  /// for the real cluster to sit just past a single ring's radius (a park
  /// or open land between the driver and the nearest town centre is common
  /// on the edge of a city). Multiple rings at different radii meaningfully
  /// raise the chance at least one point actually lands near real density.
  @MainActor
  static func refresh(near origin: CLLocationCoordinate2D, knownZones: [CLLocationCoordinate2D]) {
    let store = OkkleStore.shared
    guard store.settings.insightsEnabled else { return }
    let key = "\(Int((origin.latitude * 200).rounded())),\(Int((origin.longitude * 200).rounded()))"
    var keys = store.insightEvidence.fetchedAreaKeys
    keys = keys.filter { Date().timeIntervalSince($0.value) < fetchedKeyCooldown }
    if let last = keys[key], Date().timeIntervalSince(last) < fetchedKeyCooldown {
      store.updateInsightEvidence { $0.fetchedAreaKeys = keys }
      return
    }
    guard !fetching else { return }
    keys[key] = Date()
    store.updateInsightEvidence { $0.fetchedAreaKeys = keys }
    fetching = true
    Task {
      let found = await discover(near: origin, knownZones: knownZones)
      await MainActor.run {
        if store.settings.insightsEnabled {
          NativeExploreCandidateStore.shared.merge(found)
        }
        fetching = false
      }
    }
  }

  private static func discover(near origin: CLLocationCoordinate2D, knownZones: [CLLocationCoordinate2D]) async -> [(name: String, coordinate: CLLocationCoordinate2D, poiScore: Int)] {
    var known: [(name: String, coordinate: CLLocationCoordinate2D)] = []
    for zone in knownZones {
      if let name = await areaName(for: zone) { known.append((name.lowercased(), zone)) }
    }

    let bearings = stride(from: 0.0, to: 360.0, by: 45.0)
    let candidates = [1.2, 2.5, 4.0].flatMap { radiusKm in
      bearings.map { nativeOffsetCoordinate(origin, distanceKm: radiusKm, bearingDeg: $0) }
    }

    // Sequential, not concurrent — MKLocalSearch (like CLGeocoder) cancels
    // overlapping requests, so parallel calls would silently drop results.
    var sampled: [(CLLocationCoordinate2D, Int)] = []
    for candidate in candidates {
      let count = await poiCount(near: candidate)
      sampled.append((candidate, count))
    }

    // A flat minimum count means something different everywhere: in a
    // quiet suburb it's a real bar, but in central London where nearly
    // every sampled point clears any small number, it's just noise and
    // "the best of 16 near-ties" is arbitrary. Comparing each point
    // against this origin's own local median instead means a candidate
    // has to actually stand out from its immediate surroundings, not
    // just clear a number that means something different depending on
    // where the driver happens to live.
    let counts = sampled.map(\.1).sorted()
    let median = counts.isEmpty ? 0 : counts[counts.count / 2]
    let bar = max(nativeMinimumViableAreaPoiScore, median + max(2, median / 3))

    var scored = sampled.filter { $0.1 >= bar }
    scored.sort { $0.1 > $1.1 }

    // A genuinely quiet area (a driver near a park, or the edge of town)
    // can have real but modest density everywhere — nothing "stands out"
    // from a low, flat baseline, so the relative bar above finds nothing
    // even though there's still somewhere better than average nearby.
    // Falling back to the flat floor here means "still looking" only ever
    // shows when there's truly nothing worth a modest mention, not just
    // when nothing is a standout.
    if scored.isEmpty {
      scored = sampled.filter { $0.1 >= nativeMinimumViableAreaPoiScore }
      scored.sort { $0.1 > $1.1 }
    }

    var out: [(name: String, coordinate: CLLocationCoordinate2D, poiScore: Int)] = []
    var seenNames = Set<String>()
    for (coordinate, count) in scored {
      guard let name = await areaName(for: coordinate) else { continue }
      let candidateLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
      let matchesKnownZone = known.contains { existing in
        guard existing.name == name.lowercased() else { return false }
        let existingLocation = CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude)
        return existingLocation.distance(from: candidateLocation) < 2_000
      }
      guard !matchesKnownZone else { continue }
      if seenNames.insert(name.lowercased()).inserted {
        out.append((name: name, coordinate: coordinate, poiScore: count))
      }
      if out.count >= 3 { break }
    }
    return out
  }

  // Wider than the 400m used for the daily-plan area namer (NativeAreaNamer)
  // — a cold-start guess with only 16 sample points needs a bit more recall
  // per point than a live geocode of somewhere the driver is already at.
  private static func poiCount(near coordinate: CLLocationCoordinate2D) async -> Int {
    await nativeFoodPOICount(near: coordinate, radiusMeters: 550)
  }

  private static func areaName(for coordinate: CLLocationCoordinate2D) async -> String? {
    await withCheckedContinuation { continuation in
      CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
        continuation.resume(returning: placemarks?.first.flatMap(nativeNeighbourhoodName))
      }
    }
  }
}

/// The 32 London boroughs plus the City of London, lower-cased, with the
/// common alternate forms Apple's geocoder actually returns. For UK/London
/// addresses, subLocality itself is where a borough name shows up when
/// Apple has no finer-grained neighbourhood tag for a point — subAdministrativeArea
/// is typically empty or just "Greater London" for these addresses, so it
/// can't be used to detect the duplication the way it might elsewhere. Only
/// ever consulted for London coordinates (see nativeNeighbourhoodName), so a
/// US city that happens to share a borough's name isn't affected.
private let nativeLondonBoroughNames: Set<String> = [
  "barking and dagenham", "barnet", "bexley", "brent", "bromley", "camden",
  "city of london", "croydon", "ealing", "enfield", "greenwich", "hackney",
  "hammersmith and fulham", "haringey", "harrow", "havering", "hillingdon",
  "hounslow", "islington", "kensington and chelsea",
  "royal borough of kensington and chelsea", "kingston upon thames",
  "royal borough of kingston upon thames", "lambeth", "lewisham", "merton",
  "newham", "redbridge", "richmond upon thames",
  "richmond-upon-thames", "southwark", "sutton", "tower hamlets",
  "waltham forest", "wandsworth", "westminster", "city of westminster"
]

/// Neighbourhood first, not the street: a single road is too narrow a
/// patch for a courier to actually stake out ("Coombe Lane"?), and the
/// named district it sits in ("Wimbledon") is exactly how drivers already
/// think and talk about where to work — bigger than a road, nowhere near
/// as broad as the borough/council area or the whole town would be. A
/// borough name in subLocality ("Wandsworth", "Merton") reads exactly
/// like a real neighbourhood while being just as broad as the "whole
/// borough" case this is meant to avoid, so it's explicitly excluded
/// rather than trusted just because it filled the field.
func nativeNeighbourhoodName(from placemark: CLPlacemark) -> String? {
  if let subLocality = placemark.subLocality,
     !nativeLondonBoroughNames.contains(subLocality.lowercased()) {
    return subLocality
  }
  // No locality fallback, in any market: CLPlacemark.locality is a whole
  // city ("London", but just as unhelpfully "Chicago" or "San Francisco")
  // — as broad as the borough case above, so it's skipped the same way in
  // favor of the street, which is at least somewhere specific.
  return placemark.thoroughfare
}

/// How many nearby points of interest look delivery-relevant — food places
/// (restaurant, cafe, bakery, food market, brewery, nightlife) plus general
/// shops and pharmacies, since couriers pick up from supermarkets and
/// retail as often as restaurants — shared by the explore-area suggester
/// and the area namer below, so both agree on what counts as "somewhere
/// worth recommending" rather than any resolvable place name.
func nativeFoodPOICount(near coordinate: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) async -> Int {
  // Two independent, differently-sourced counts, taken together as
  // whichever sees more — Apple's own POI database and OSM's community
  // one have different gaps (Apple's is often thinner in outer suburbs;
  // OSM's coverage varies by how actively an area's been mapped), so
  // this is closer to "how many food places are really here" than
  // either alone, without double-counting the ones both happen to know
  // about the way a straight sum would.
  async let mapKit = nativeMapKitFoodPOICount(near: coordinate, radiusMeters: radiusMeters)
  async let overpass = nativeOverpassFoodPOICount(near: coordinate, radiusMeters: radiusMeters)
  return await max(mapKit, overpass)
}

private func nativeMapKitFoodPOICount(near coordinate: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) async -> Int {
  await withCheckedContinuation { continuation in
    let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radiusMeters)
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .nightlife, .store, .pharmacy])
    MKLocalSearch(request: request).start { response, _ in
      continuation.resume(returning: response?.mapItems.count ?? 0)
    }
  }
}

/// Free, no-key, community-maintained supplement to Apple's own POI
/// database via OpenStreetMap's public Overpass API — some entries here
/// even carry explicit takeaway/delivery tags Apple's database doesn't
/// expose at all. Silently returns 0 on any failure (timeout, no
/// network, the public instance being over capacity) so an Overpass
/// outage only ever loses this one signal, never blocks the
/// already-best-effort area-suggestion scoring around it.
private func nativeOverpassFoodPOICount(near coordinate: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) async -> Int {
  let radius = Int(radiusMeters)
  let query = """
  [out:json][timeout:8];
  (
    node["amenity"~"^(restaurant|fast_food|cafe|pub|bar|pharmacy)$"](around:\(radius),\(coordinate.latitude),\(coordinate.longitude));
    node["shop"~"^(bakery|supermarket|convenience|department_store|general|variety_store|mall|kiosk|chemist)$"](around:\(radius),\(coordinate.latitude),\(coordinate.longitude));
  );
  out count;
  """
  guard let url = URL(string: "https://overpass-api.de/api/interpreter"),
        let body = "data=\(query)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return 0 }

  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.httpBody = Data(body.utf8)
  request.timeoutInterval = 8

  do {
    let (data, _) = try await URLSession.shared.data(for: request)
    let decoded = try JSONDecoder().decode(NativeOverpassCountResponse.self, from: data)
    return decoded.elements.first.flatMap { Int($0.tags.total) } ?? 0
  } catch {
    return 0
  }
}

private struct NativeOverpassCountResponse: Decodable {
  struct Element: Decodable {
    struct Tags: Decodable {
      let total: String
    }
    let tags: Tags
  }
  let elements: [Element]
}

/// A coloured overlay circle for one zone — a plain MKCircle plus the weight
/// that decides its colour.
final class NativeZoneCircle: MKCircle {
  var weight: Double = 0.5
  var rendersAsGlow = false
}

/// A cheap, cached "does this look like a food-delivery area at all" prior,
/// used to steer zone ranking while a zone has little or no real delivery
/// history yet — same cache-then-resolve-async shape as NativeAreaNamer, so
/// build() can call it synchronously and just get nil until the on-device
/// MapKit lookup resolves.
@MainActor
final class NativeZonePOIPrior: ObservableObject {
  static let shared = NativeZonePOIPrior()
  var scores: [String: Double] { OkkleStore.shared.insightEvidence.poiPriorScores }
  private var pending: [(key: String, coordinate: CLLocationCoordinate2D)] = []
  private var enqueued: Set<String> = []
  private var busy = false
  // A handful of nearby restaurants is already "clearly food-relevant" —
  // beyond this the score just stays capped at 1, rather than rewarding
  // whichever cell happens to sit in the single densest high street.
  private static let saturationCount = 8.0

  func priorScore(for coordinate: CLLocationCoordinate2D) -> Double? {
    guard OkkleStore.shared.settings.insightsEnabled else { return nil }
    let key = "\(Int((coordinate.latitude * 200).rounded())),\(Int((coordinate.longitude * 200).rounded()))"
    if let cached = scores[key] { return cached }
    if !enqueued.contains(key) {
      enqueued.insert(key)
      pending.append((key, coordinate))
      drain()
    }
    return nil
  }

  private func drain() {
    guard OkkleStore.shared.settings.insightsEnabled, !busy, !pending.isEmpty else { return }
    busy = true
    let job = pending.removeFirst()
    Task {
      let count = await nativeFoodPOICount(near: job.coordinate, radiusMeters: 500)
      guard OkkleStore.shared.settings.insightsEnabled else {
        self.busy = false
        return
      }
      OkkleStore.shared.updateInsightEvidence {
        $0.poiPriorScores[job.key] = min(Double(count) / Self.saturationCount, 1.0)
      }
      self.objectWillChange.send()
      self.busy = false
      try? await Task.sleep(nanoseconds: 250_000_000)
      self.drain()
    }
  }
}

/// Turns a zone coordinate into a short, human area name ("Soho", "Camden") for
/// the daily plan text. On-device reverse geocoding, cached so it only runs
/// once per rounded coordinate; fails silently (the caller just omits the name)
/// — including when the street resolves fine but there's nothing food-relevant
/// nearby, since a recognisable name is worse than no name if it just sends a
/// driver to an empty street or a park.
@MainActor
final class NativeAreaNamer: ObservableObject {
  static let shared = NativeAreaNamer()
  @Published private(set) var names: [String: String] = [:]
  private let geocoder = CLGeocoder()
  // CLGeocoder cancels overlapping requests, so asking for several areas at once
  // leaves all but one unresolved. Queue them and resolve one at a time.
  private var pending: [(key: String, coordinate: CLLocationCoordinate2D)] = []
  private var enqueued: Set<String> = []
  private var busy = false

  func name(for coordinate: CLLocationCoordinate2D) -> String? {
    guard OkkleStore.shared.settings.insightsEnabled else { return nil }
    let key = "\(Int((coordinate.latitude * 200).rounded())),\(Int((coordinate.longitude * 200).rounded()))"
    if let cached = names[key] { return cached }
    if !enqueued.contains(key) {
      enqueued.insert(key)
      pending.append((key, coordinate))
      drain()
    }
    return nil
  }

  private func drain() {
    guard OkkleStore.shared.settings.insightsEnabled, !busy, !pending.isEmpty else { return }
    busy = true
    let job = pending.removeFirst()
    geocoder.reverseGeocodeLocation(CLLocation(latitude: job.coordinate.latitude, longitude: job.coordinate.longitude)) { [weak self] placemarks, _ in
      guard let self else { return }
      Task { @MainActor in
        guard OkkleStore.shared.settings.insightsEnabled else {
          self.busy = false
          return
        }
        // Aim for the named district/neighbourhood a driver can actually
        // head to ("Wimbledon"), not a single street ("The Broadway") —
        // too narrow a patch to stake out — and never a whole borough
        // ("Merton", "Wandsworth") which is too broad to act on. See
        // nativeNeighbourhoodName for how a borough name masquerading as
        // subLocality gets caught.
        if let p = placemarks?.first,
           let area = nativeNeighbourhoodName(from: p) {
          // A resolvable name isn't enough on its own — check there's
          // actually somewhere to deliver from/to nearby before naming it,
          // otherwise a quiet back road or a park street name can end up
          // confidently recommended as "where to go".
          let hasFoodNearby = await nativeFoodPOICount(near: job.coordinate, radiusMeters: 500) > 0
          if hasFoodNearby {
            self.names[job.key] = area
          } else {
            self.enqueued.remove(job.key)
          }
        } else {
          // Let a later pass retry (throttle/no-result) rather than caching a miss.
          self.enqueued.remove(job.key)
        }
        self.busy = false
        // Small gap keeps us the right side of the geocoder's rate limit.
        try? await Task.sleep(nanoseconds: 250_000_000)
        self.drain()
      }
    }
  }
}

// MARK: - Weather (Open-Meteo — free, no API key)
