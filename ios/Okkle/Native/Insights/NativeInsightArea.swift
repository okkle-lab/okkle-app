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
struct NativeOutcomeSample: Codable {
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
  @Published private(set) var samples: [NativeOutcomeSample] = []
  private let storageKey = "uk.okkle.native.outcome.samples.v1"

  init() { load() }

  func record(amount: Double, period: NativePayPeriod, wasPredictedPeakDay: Bool) {
    guard amount > 0 else { return }
    samples.append(NativeOutcomeSample(date: Date(), period: period, amount: amount, wasPredictedPeakDay: wasPredictedPeakDay))
    // A rolling log, not a growing ledger — recent evidence should dominate.
    if samples.count > 40 { samples.removeFirst(samples.count - 40) }
    save()
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

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
          let saved = try? JSONDecoder().decode([NativeOutcomeSample].self, from: data) else { return }
    samples = saved
  }

  private func save() {
    if let data = try? JSONEncoder().encode(samples) {
      UserDefaults.standard.set(data, forKey: storageKey)
    }
  }
}

// MARK: - Areas to try — a silent background layer, not a UI feature.
//
// There's no order-volume data to learn real demand from, so any "try this
// area" guess is a guess. Rather than show it to the driver, this layer
// quietly scores nearby candidates by restaurant density, then watches real
// passive visits: if the driver ever naturally drives near a candidate, that
// visit's day becomes a trial. Enough trials with decent earnings and the
// candidate is "validated" — at which point it's simply real data, already
// flowing into the normal zone/ranking pipeline like anywhere else the driver
// has worked. That's the automatic feedback loop: no manual promotion, no
// dashboard, just evidence accumulating quietly until a guess earns its way
// into being real.

/// One candidate the background layer discovered — persisted so trial
/// evidence survives across launches.
struct NativeExploreCandidate: Codable, Identifiable {
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

@MainActor
final class NativeExploreCandidateStore: ObservableObject {
  static let shared = NativeExploreCandidateStore()
  @Published private(set) var candidates: [NativeExploreCandidate] = []
  private let storageKey = "uk.okkle.native.explore.candidates.v1"

  init() { load() }

  /// Add newly discovered candidates, keeping any trial evidence already
  /// collected for ones we're already tracking (matched by name).
  func merge(_ discovered: [(name: String, coordinate: CLLocationCoordinate2D, poiScore: Int)]) {
    let known = Set(candidates.map { $0.name.lowercased() })
    for area in discovered where !known.contains(area.name.lowercased()) {
      candidates.append(NativeExploreCandidate(name: area.name, latitude: area.coordinate.latitude,
                                               longitude: area.coordinate.longitude, poiScore: area.poiScore,
                                               discoveredAt: Date()))
    }
    trim()
    save()
  }

  /// Called on every real passive visit — the feedback half of the loop. If
  /// the visit lands near a candidate we're quietly testing, log a trial.
  func recordVisit(_ coordinate: CLLocationCoordinate2D, dayIncome: Double?) {
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
    if changed { save() }
  }

  private func trim() {
    // A lightweight exploration log, not a growing database: drop anything
    // that's sat untouched for 90 days, and cap the total tracked.
    let cutoff = Date().addingTimeInterval(-90 * 86_400)
    candidates.removeAll { $0.discoveredAt < cutoff && $0.timesNearby == 0 }
    if candidates.count > 30 { candidates = Array(candidates.suffix(30)) }
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
          let saved = try? JSONDecoder().decode([NativeExploreCandidate].self, from: data) else { return }
    candidates = saved
  }

  private func save() {
    if let data = try? JSONEncoder().encode(candidates) {
      UserDefaults.standard.set(data, forKey: storageKey)
    }
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
  private static var fetchedForKey: String?
  private static var fetching = false

  /// Lay out a ring of candidates 2km out around the driver, score them by
  /// restaurant density, and hand the top two to the store — excluding
  /// anywhere that resolves to a name the driver already knows. Streets can
  /// run for over a kilometre, so excluding by *name* (not raw distance) is
  /// what stops a re-suggesting a street the driver already partly works.
  @MainActor
  static func refresh(near origin: CLLocationCoordinate2D, knownZones: [CLLocationCoordinate2D]) {
    let key = "\(Int((origin.latitude * 200).rounded())),\(Int((origin.longitude * 200).rounded()))"
    guard key != fetchedForKey, !fetching else { return }
    fetchedForKey = key
    fetching = true
    Task {
      let found = await discover(near: origin, knownZones: knownZones)
      await MainActor.run {
        NativeExploreCandidateStore.shared.merge(found)
        fetching = false
      }
    }
  }

  private static func discover(near origin: CLLocationCoordinate2D, knownZones: [CLLocationCoordinate2D]) async -> [(name: String, coordinate: CLLocationCoordinate2D, poiScore: Int)] {
    var known = Set<String>()
    for zone in knownZones {
      if let name = await areaName(for: zone) { known.insert(name.lowercased()) }
    }

    let candidates = stride(from: 0.0, to: 360.0, by: 45.0)
      .map { nativeOffsetCoordinate(origin, distanceKm: 2.0, bearingDeg: $0) }

    // Sequential, not concurrent — MKLocalSearch (like CLGeocoder) cancels
    // overlapping requests, so parallel calls would silently drop results.
    var scored: [(CLLocationCoordinate2D, Int)] = []
    for candidate in candidates {
      let count = await poiCount(near: candidate)
      if count > 0 { scored.append((candidate, count)) }
    }
    scored.sort { $0.1 > $1.1 }

    var out: [(name: String, coordinate: CLLocationCoordinate2D, poiScore: Int)] = []
    var seenNames = Set<String>()
    for (coordinate, count) in scored {
      guard let name = await areaName(for: coordinate) else { continue }
      guard !known.contains(name.lowercased()) else { continue }
      if seenNames.insert(name.lowercased()).inserted {
        out.append((name: name, coordinate: coordinate, poiScore: count))
      }
      if out.count >= 2 { break }
    }
    return out
  }

  private static func poiCount(near coordinate: CLLocationCoordinate2D) async -> Int {
    await nativeFoodPOICount(near: coordinate, radiusMeters: 400)
  }

  private static func areaName(for coordinate: CLLocationCoordinate2D) async -> String? {
    await withCheckedContinuation { continuation in
      CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
        continuation.resume(returning: placemarks?.first.flatMap { $0.thoroughfare ?? $0.subLocality ?? $0.locality })
      }
    }
  }
}

/// How many nearby points of interest look food/delivery-relevant (restaurant,
/// cafe, bakery, food market, brewery, nightlife) — shared by the explore-area
/// suggester and the area namer below, so both agree on what counts as
/// "somewhere worth recommending" rather than any resolvable place name.
func nativeFoodPOICount(near coordinate: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) async -> Int {
  await withCheckedContinuation { continuation in
    let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radiusMeters)
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .nightlife])
    MKLocalSearch(request: request).start { response, _ in
      continuation.resume(returning: response?.mapItems.count ?? 0)
    }
  }
}

/// A coloured overlay circle for one zone — a plain MKCircle plus the weight
/// that decides its colour.
final class NativeZoneCircle: MKCircle {
  var weight: Double = 0.5
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
    guard !busy, !pending.isEmpty else { return }
    busy = true
    let job = pending.removeFirst()
    geocoder.reverseGeocodeLocation(CLLocation(latitude: job.coordinate.latitude, longitude: job.coordinate.longitude)) { [weak self] placemarks, _ in
      guard let self else { return }
      Task { @MainActor in
        // Aim for the tightest patch a driver can actually head to: a street
        // ("The Broadway") or a small district, never a whole borough ("Merton",
        // "City of Westminster") which is too broad to act on.
        if let p = placemarks?.first,
           let area = p.thoroughfare ?? p.subLocality ?? p.locality {
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

