import CoreLocation
import EventKit
import MapKit
import SwiftUI
import UIKit

private let nativeInsightPromptAnimation = Animation.spring(response: 0.46, dampingFraction: 0.72, blendDuration: 0.08)

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
func nativeHeatColor(_ t: Double) -> Color {
  let stops: [(Double, Double, Double, Double)] = [
    (0.00, 0.20, 0.47, 0.93),
    (0.35, 0.10, 0.66, 0.62),
    (0.60, 0.24, 0.72, 0.30),
    (0.80, 0.95, 0.66, 0.23),
    (1.00, 0.86, 0.16, 0.16)
  ]
  let clamped = max(0, min(1, t))
  for i in 1..<stops.count {
    guard clamped <= stops[i].0 else { continue }
    let (t0, r0, g0, b0) = stops[i - 1]
    let (t1, r1, g1, b1) = stops[i]
    let f = t1 > t0 ? (clamped - t0) / (t1 - t0) : 0
    return Color(red: r0 + (r1 - r0) * f, green: g0 + (g1 - g0) * f, blue: b0 + (b1 - b0) * f)
  }
  let last = stops.last!
  return Color(red: last.1, green: last.2, blue: last.3)
}

func nativeHeatUIColor(_ t: Double) -> UIColor { UIColor(nativeHeatColor(t)) }

struct NativeHeatLegend: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Quiet")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
        Capsule()
          .fill(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.05).map(nativeHeatColor), startPoint: .leading, endPoint: .trailing))
          .frame(maxWidth: .infinity)
          .frame(height: 10)
        Text("Busiest")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(OkkleColor.muted)
      }
    }
  }
}

// MARK: - One-shot location (so the map has somewhere to show before any data exists)

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
    await withCheckedContinuation { continuation in
      let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 400)
      request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .nightlife])
      MKLocalSearch(request: request).start { response, _ in
        continuation.resume(returning: response?.mapItems.count ?? 0)
      }
    }
  }

  private static func areaName(for coordinate: CLLocationCoordinate2D) async -> String? {
    await withCheckedContinuation { continuation in
      CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
        continuation.resume(returning: placemarks?.first.flatMap { $0.thoroughfare ?? $0.subLocality ?? $0.locality })
      }
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
/// once per rounded coordinate; fails silently (the caller just omits the name).
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
          self.names[job.key] = area
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

func nativeWeatherSymbol(_ code: Int) -> String {
  switch code {
  case 0: return "sun.max.fill"
  case 1, 2: return "cloud.sun.fill"
  case 3: return "cloud.fill"
  case 45, 48: return "cloud.fog.fill"
  case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
  case 61, 63, 65, 66, 67: return "cloud.rain.fill"
  case 71, 73, 75, 77: return "snowflake"
  case 80, 81, 82: return "cloud.heavyrain.fill"
  case 85, 86: return "snowflake"
  case 95, 96, 99: return "cloud.bolt.rain.fill"
  default: return "cloud.fill"
  }
}

func nativeWeatherLabel(_ code: Int) -> String {
  switch code {
  case 0: return "Clear"
  case 1, 2: return "Partly cloudy"
  case 3: return "Cloudy"
  case 45, 48: return "Fog"
  case 51, 53, 55, 56, 57: return "Drizzle"
  case 61, 63, 65: return "Rain"
  case 66, 67: return "Freezing rain"
  case 71, 73, 75, 77: return "Snow"
  case 80, 81, 82: return "Showers"
  case 85, 86: return "Snow showers"
  case 95, 96, 99: return "Thunderstorm"
  default: return "Cloudy"
  }
}

struct NativeHourWeather: Identifiable, Equatable {
  let hour: Int
  let temperature: Double
  let precipitation: Double
  let precipProbability: Int
  let code: Int

  var id: Int { hour }
  var isWet: Bool { precipitation >= 0.15 || precipProbability >= 55 }
  var isCold: Bool { temperature <= 7 }
  /// Rain and cold both drive up delivery demand while thinning out drivers —
  /// classically the better-paying conditions to be out in.
  var boostsDemand: Bool { isWet || isCold }
  var symbol: String { nativeWeatherSymbol(code) }
  var label: String { nativeWeatherLabel(code) }
}

struct NativeDayWeather: Equatable {
  let hours: [NativeHourWeather]
  func at(_ hour: Int) -> NativeHourWeather? { hours.first { $0.hour == hour } }
}

/// Fetches today's hourly forecast from Open-Meteo (no key, HTTPS, on-device),
/// throttled so it only refetches when stale or you've moved a few km. Fails
/// silently — weather is an extra layer, never load-bearing.
@MainActor
final class NativeWeatherService: ObservableObject {
  static let shared = NativeWeatherService()
  @Published private(set) var today: NativeDayWeather?

  private var lastCoord: CLLocationCoordinate2D?
  private var lastFetch: Date?
  private var seeded = false

  func seed(_ weather: NativeDayWeather) {
    today = weather
    seeded = true
  }

  func refresh(for coordinate: CLLocationCoordinate2D) {
    guard !seeded else { return }
    if let lc = lastCoord, let lf = lastFetch,
       Date().timeIntervalSince(lf) < 1800,
       CLLocation(latitude: lc.latitude, longitude: lc.longitude)
         .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 5000 {
      return
    }
    lastCoord = coordinate
    lastFetch = Date()
    Task { await fetch(coordinate) }
  }

  private func fetch(_ coordinate: CLLocationCoordinate2D) async {
    var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
    comps?.queryItems = [
      URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
      URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
      URLQueryItem(name: "hourly", value: "temperature_2m,precipitation,precipitation_probability,weather_code"),
      URLQueryItem(name: "timezone", value: "auto"),
      URLQueryItem(name: "forecast_days", value: "1")
    ]
    guard let url = comps?.url else { return }
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      let decoded = try JSONDecoder().decode(NativeOpenMeteoResponse.self, from: data)
      today = decoded.dayWeather()
    } catch {
      // silent — no weather layer this session
    }
  }
}

private struct NativeOpenMeteoResponse: Decodable {
  struct Hourly: Decodable {
    let time: [String]
    let temperature_2m: [Double?]
    let precipitation: [Double?]
    let precipitation_probability: [Int?]
    let weather_code: [Int?]
  }
  let hourly: Hourly

  func dayWeather() -> NativeDayWeather {
    var hours: [NativeHourWeather] = []
    for (i, stamp) in hourly.time.enumerated() {
      guard let hh = stamp.split(separator: "T").last?.prefix(2), let hour = Int(hh) else { continue }
      hours.append(NativeHourWeather(
        hour: hour,
        temperature: hourly.temperature_2m[safe: i]?.flatMap { $0 } ?? 0,
        precipitation: hourly.precipitation[safe: i]?.flatMap { $0 } ?? 0,
        precipProbability: hourly.precipitation_probability[safe: i]?.flatMap { $0 } ?? 0,
        code: hourly.weather_code[safe: i]?.flatMap { $0 } ?? 0
      ))
    }
    return NativeDayWeather(hours: hours)
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

/// Demo forecast for the SEED_DEMO launch flag: a wet, cold 6–8pm so the demand
/// signal has something to react to.
func nativeDemoWeather() -> NativeDayWeather {
  let hours = (0..<24).map { h -> NativeHourWeather in
    let wet = (18...20).contains(h)
    return NativeHourWeather(hour: h, temperature: wet ? 8 : 15,
                             precipitation: wet ? 1.4 : 0, precipProbability: wet ? 85 : 10,
                             code: wet ? 63 : 2)
  }
  return NativeDayWeather(hours: hours)
}

// MARK: - Map (tracked routes + zone colouring, defaulting to the user's location)

/// A numbered marker for a ranked top area on the detail map.
final class NativeRankAnnotation: MKPointAnnotation {
  var rank: Int = 0
  var weight: Double = 0.5
}

struct NativeShiftMapRepresentable: UIViewRepresentable {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  var interactive: Bool = false
  var pinLimit: Int = 5
  @ObservedObject private var locator = NativeOneShotLocator.shared
  @ObservedObject private var areaNamer = NativeAreaNamer.shared

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.isUserInteractionEnabled = interactive
    mapView.showsCompass = interactive
    mapView.showsScale = interactive
    mapView.isPitchEnabled = false
    mapView.showsUserLocation = true
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    mapView.removeOverlays(mapView.overlays)
    mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

    for trip in trips {
      let coordinates = trip.points.map(\.coordinate)
      guard coordinates.count > 1 else { continue }
      let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
      mapView.addOverlay(polyline)
    }

    // Zones layer gradually as stops accumulate — with none yet, nothing draws
    // and the map just centres on you; each new pattern adds a coloured cell.
    for zone in zones {
      let circle = NativeZoneCircle(center: zone.coordinate, radius: 220)
      circle.weight = zone.weight
      mapView.addOverlay(circle)
    }

    // Numbered pins that line up with the "Where to go" list — pin 2 is list
    // row 2, the same named place — so the ranking reads as one idea.
    let ranked = nativeRankedAreas(zones, near: locator.coordinate, namer: areaNamer, limit: pinLimit)
    for area in ranked {
      let pin = NativeRankAnnotation()
      pin.coordinate = area.coordinate
      pin.rank = area.rank
      pin.weight = area.weight
      mapView.addAnnotation(pin)
    }

    // Both the mini preview and the full detail map centre on you — when your
    // areas are spread miles apart, fitting them all zooms out to the whole
    // city and the pins become useless dots. Staying anchored near your
    // current spot keeps it readable; on the interactive map you can still
    // pan out to see the rest.
    if !interactive {
      let focus = ranked.first?.coordinate ?? locator.coordinate ?? CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)
      mapView.setRegion(MKCoordinateRegion(center: focus, span: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.055)), animated: false)
    } else {
      let center = locator.coordinate ?? ranked.first?.coordinate ?? CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)
      mapView.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)), animated: false)
    }
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      if let polyline = overlay as? MKPolyline {
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = UIColor(red: 0.20, green: 0.47, blue: 0.93, alpha: 0.55)
        renderer.lineWidth = 4
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
      }
      if let circle = overlay as? NativeZoneCircle {
        let color = nativeHeatUIColor(circle.weight)
        let renderer = MKCircleRenderer(circle: circle)
        renderer.fillColor = color.withAlphaComponent(0.34)
        renderer.strokeColor = color.withAlphaComponent(0.8)
        renderer.lineWidth = 1.5
        return renderer
      }
      return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      guard let rank = annotation as? NativeRankAnnotation else { return nil }
      let id = "rank"
      let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
      view.annotation = annotation
      let size: CGFloat = 26
      let badge = UILabel(frame: CGRect(x: 0, y: 0, width: size, height: size))
      badge.text = "\(rank.rank)"
      badge.textAlignment = .center
      badge.textColor = .white
      badge.font = .systemFont(ofSize: 13, weight: .heavy)
      badge.backgroundColor = UIColor(OkkleColor.brand)   // rank marker, not a heat value
      badge.layer.cornerRadius = size / 2
      badge.layer.borderColor = UIColor.white.cgColor
      badge.layer.borderWidth = 2
      badge.layer.masksToBounds = true
      let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
      view.image = renderer.image { _ in badge.layer.render(in: UIGraphicsGetCurrentContext()!) }
      view.centerOffset = .zero
      return view
    }
  }
}

/// A small live heat-map of your busy areas, right on the daily panel — a glance
/// tells you where the warm patches are. Tap to open the full explorable map.
struct NativeZoneMiniMap: View {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  @State private var showDetail = false

  var body: some View {
    Button { showDetail = true } label: {
      ZStack(alignment: .bottomTrailing) {
        NativeShiftMapRepresentable(trips: trips, zones: zones, interactive: false, pinLimit: 3)
          .frame(height: 150)
          .allowsHitTesting(false)
        // Little affordance so it clearly opens something bigger.
        HStack(spacing: 5) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .bold))
          Text("Explore")
            .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(OkkleColor.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(10)
      }
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $showDetail) {
      NativeShiftMapDetailView(trips: trips, zones: zones)
    }
  }
}

/// A ranked list of your busiest areas (top few near you). Resolves area names
/// on-device and de-dupes, so "Camden · Soho · Islington" reads cleanly.
/// A clean, grouped list of your best areas — each with *when* it's busy for
/// you, so "where to go" and "when to go" read as one line.
struct NativeTopAreasList: View {
  let zones: [NativeZonePoint]
  var limit: Int = 5
  /// Show a thin bar of how much of your work each area carries — turns a plain
  /// rank into a sense of *how dominant* the top patch really is.
  var showShareBar: Bool = false
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  @ObservedObject private var locator = NativeOneShotLocator.shared

  var body: some View {
    let rows = nativeRankedAreas(zones, near: locator.coordinate, namer: areaNamer, limit: limit)
    if !rows.isEmpty {
      VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, area in
          HStack(spacing: 12) {
            // Numbered badge — one brand colour so the number carries the rank.
            // (Heat colours are reserved for the busy-hours graph and map, to
            // avoid reading rank and busyness as the same scale.)
            Text("\(area.rank)")
              .font(.system(size: 13, weight: .heavy))
              .foregroundStyle(.white)
              .frame(width: 24, height: 24)
              .background(OkkleColor.brand, in: Circle())
            VStack(alignment: .leading, spacing: showShareBar ? 5 : 1) {
              Text(area.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OkkleColor.ink)
              Text(area.time.map { "Busy \($0)" } ?? "One of your patches")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OkkleColor.muted)
              if showShareBar {
                GeometryReader { geo in
                  ZStack(alignment: .leading) {
                    Capsule().fill(OkkleColor.muted.opacity(0.12)).frame(height: 4)
                    Capsule().fill(OkkleColor.brand).frame(width: max(6, geo.size.width * area.weight), height: 4)
                  }
                }
                .frame(height: 4)
                .padding(.top, 1)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.vertical, 10)
          if index < rows.count - 1 {
            Divider().padding(.leading, 36)
          }
        }
      }
    } else {
      Text("Your best areas will show here once a few more shifts are tracked.")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }
  }
}

struct NativeShiftMapDetailView: View {
  let trips: [NativeTrip]
  let zones: [NativeZonePoint]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        NativeShiftMapRepresentable(trips: trips, zones: zones, interactive: true)
          .ignoresSafeArea(edges: .bottom)
        VStack(spacing: 12) {
          Text("Numbered pins are your busiest areas near you, ranked 1–5. Warmer patches are where you pick up and drop off most.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          NativeHeatLegend()
        }
        .padding(16)
        .background(.regularMaterial)
      }
      .navigationTitle("Where you earn")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }.fontWeight(.bold)
        }
      }
    }
  }
}

// MARK: - The main card: your shift plan (Today / This week / Monthly / Yearly)

/// Which window the shift panel reflects. "Today" reads the existing
/// day-plan logic unchanged; the other three re-run the same weekly-panel
/// metrics over a wider or narrower slice of the same visit history, so the
/// numbers are always directly comparable across periods.
enum NativeInsightPeriod: Int, CaseIterable, Identifiable {
  case today, week, month, year

  var id: Int { rawValue }

  var label: String {
    switch self {
    case .today: return "Today"
    case .week: return "This week"
    case .month: return "Monthly"
    case .year: return "Yearly"
    }
  }

  /// Rolling lookback in days — nil for "Today", which doesn't rebuild the
  /// shift model at all, it just reads todayPlan off the full history.
  var lookbackDays: Int? {
    switch self {
    case .today: return nil
    case .week: return 7
    case .month: return 30
    case .year: return 365
    }
  }
}

/// Reports each carousel page's natural height, since a paged TabView
/// doesn't size itself to content — the card resizes to whichever page is
/// currently showing instead of leaving blank space or clipping.
private struct NativeInsightPageHeightKey: PreferenceKey {
  static var defaultValue: [NativeInsightPeriod: CGFloat] = [:]
  static func reduce(value: inout [NativeInsightPeriod: CGFloat], nextValue: () -> [NativeInsightPeriod: CGFloat]) {
    value.merge(nextValue()) { _, new in new }
  }
}

struct NativeInsightPeriodTabs: View {
  @Binding var period: NativeInsightPeriod

  var body: some View {
    HStack(spacing: 8) {
      ForEach(NativeInsightPeriod.allCases) { p in
        let selected = p == period
        Text(p.label)
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(selected ? Color.white : OkkleColor.ink)
          .padding(.horizontal, 14)
          .padding(.vertical, 7)
          .background(selected ? OkkleColor.brand : OkkleColor.muted.opacity(0.12), in: Capsule())
          .contentShape(Capsule())
          .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { period = p }
          }
      }
      Spacer(minLength: 0)
    }
  }
}

struct NativeShiftPatternsCard: View {
  let shift: NativeShiftInsights
  let visits: [NativeVisit]
  let trips: [NativeTrip]
  @Binding var autoTrackTrips: Bool
  @EnvironmentObject private var store: OkkleStore
  @State private var period: NativeInsightPeriod = .today
  @State private var pageHeights: [NativeInsightPeriod: CGFloat] = [:]

  /// Same metrics as "This week" for every non-today period — just fed a
  /// wider or narrower slice of the same visit history before re-running
  /// NativeShiftInsights.build, so month/year are directly comparable.
  private func shift(for period: NativeInsightPeriod) -> NativeShiftInsights {
    guard let days = period.lookbackDays else { return shift }
    let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    let scoped = visits.filter { $0.arrival >= cutoff }
    return NativeShiftInsights.build(visits: scoped, store: store)
  }

  var body: some View {
    if !autoTrackTrips {
      NativeAiCard { offState }
        .transition(.nativeInsightSetupCard)
    } else if !shift.hasData {
      NativeAiCard { buildingState }
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    } else {
      VStack(alignment: .leading, spacing: 14) {
        NativeInsightPeriodTabs(period: $period)

        TabView(selection: $period) {
          ForEach(NativeInsightPeriod.allCases) { p in
            Group {
              if p == .today {
                NativeDailyInsightPanel(shift: shift, trips: trips)
              } else {
                NativeWeeklyInsightPanel(shift: shift(for: p))
              }
            }
            .background(GeometryReader { geo in
              Color.clear.preference(key: NativeInsightPageHeightKey.self, value: [p: geo.size.height])
            })
            .tag(p)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pageHeights[period] ?? 200)
        .onPreferenceChange(NativeInsightPageHeightKey.self) { pageHeights = $0 }
        .animation(.easeInOut(duration: 0.2), value: pageHeights[period])
      }
      .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
  }

  private var offState: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Know exactly when and where to work")
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
      Text("Turn on automatic tracking and Okkle learns your best times and areas passively — no screenshots, no shortcuts.")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)
      Toggle("Automatic trip tracking", isOn: $autoTrackTrips)
        .font(.system(size: 17, weight: .bold))
        .tint(OkkleColor.brand)
    }
  }

  /// Cold start: sensible built-in guidance so a day-1 driver still gets
  /// something useful while their own pattern accrues. Clearly generic.
  private var buildingState: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Learning your week")
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("This fills in automatically as you drive. Until then, what tends to work for most couriers:")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      VStack(spacing: 0) {
        baselineRow("fork.knife", "Dinner beats mid-afternoon", "5–9pm is usually your window", true)
        baselineRow("calendar", "Weekend evenings are strongest", "Friday to Sunday", true)
        baselineRow("cloud.rain.fill", "Rain and cold pay better", "More orders, fewer drivers", true)
        baselineRow("fuelpump.fill", "Cut the roaming", "Idle miles quietly eat profit", false)
      }
    }
  }

  private func baselineRow(_ symbol: String, _ title: String, _ sub: String, _ divider: Bool) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(OkkleColor.brand)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(OkkleColor.ink)
          Text(sub).font(.system(size: 13, weight: .medium)).foregroundStyle(OkkleColor.muted)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 10)
      if divider { Divider().padding(.leading, 36) }
    }
  }
}

// MARK: - Daily panel

struct NativeDailyInsightPanel: View {
  let shift: NativeShiftInsights
  let trips: [NativeTrip]
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  @ObservedObject private var weather = NativeWeatherService.shared
  @ObservedObject private var locator = NativeOneShotLocator.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let plan = shift.todayPlan {
        // Panel 1 — WHEN: the one thing to do, plus the busy shape of the day.
        NativeAiCard {
          VStack(alignment: .leading, spacing: 16) {
            heroSection(plan)
            if let brk = plan.breakWindow {
              Label("Quiet \(brk.label) — a good window for your break.", systemImage: "cup.and.saucer.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OkkleColor.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("WHEN IT'S BUSY")
                  .font(.system(size: 12, weight: .heavy)).tracking(0.5)
                  .foregroundStyle(OkkleColor.muted)
                Spacer()
                NativeBusyLegend()
              }
              NativeHourStrip(hourCounts: plan.hourCounts)
            }
          }
        }

        // Panel 2 — WHERE: your best patches and a live heat-map to explore.
        NativeAiCard {
          VStack(alignment: .leading, spacing: 12) {
            section("WHERE TO GO") {
              NativeTopAreasList(zones: shift.zones, limit: 3)
            }
            NativeZoneMiniMap(trips: trips, zones: shift.zones)
            Text("Each pin matches the list above — 1 is your busiest patch. Tap the map to explore full-screen.")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .onAppear {
      locator.request()
      if let c = locator.coordinate { weather.refresh(for: c) }
    }
    .onChange(of: locator.coordinate?.latitude) { _ in
      if let c = locator.coordinate { weather.refresh(for: c) }
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 12, weight: .heavy)).tracking(0.5)
        .foregroundStyle(OkkleColor.muted)
      content()
    }
  }

  /// How sure Okkle is, as a labelled chip (not a menu) — signal bars + words so
  /// it reads as "how much data is behind this", not a tappable control.
  private var confidenceChip: some View {
    HStack(spacing: 5) {
      HStack(alignment: .bottom, spacing: 1.5) {
        ForEach(0..<3, id: \.self) { i in
          RoundedRectangle(cornerRadius: 0.5)
            .fill(i < shift.confidence.dots ? OkkleColor.brand : OkkleColor.muted.opacity(0.25))
            .frame(width: 3, height: 4 + CGFloat(i) * 3)
        }
      }
      Text("Confidence: \(shift.confidence.level)")
        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
        .foregroundStyle(OkkleColor.muted)
    }
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(OkkleColor.muted.opacity(0.08), in: Capsule())
    .accessibilityLabel("Confidence: \(shift.confidence.level)")
  }

  // MARK: Hero — one calm, confident instruction (Apple-style: type, not chrome)

  private func heroSection(_ plan: NativeDayPlan) -> some View {
    let hero = heroContent(plan)
    return VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        Text(plan.isToday ? "TODAY · \(Calendar.current.weekdaySymbols[plan.weekday].uppercased())"
                          : "NEXT: \(Calendar.current.weekdaySymbols[plan.weekday].uppercased())")
          .font(.system(size: 12, weight: .heavy)).tracking(0.5)
          .foregroundStyle(hero.color)
        Spacer()
        confidenceChip
      }
      Text(hero.title)
        .font(.system(size: 27, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .fixedSize(horizontal: false, vertical: true)
      Text(hero.detail)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// One instruction, chosen by priority: big night → in a window now → window
  /// coming → wound down → next working day. Weather escalates, never competes.
  private func heroContent(_ plan: NativeDayPlan) -> (symbol: String, color: Color, title: String, detail: String) {
    let strongDay = shift.weekdayDetails.prefix(3).contains { $0.weekday == plan.weekday }
    let dayName = Calendar.current.weekdaySymbols[plan.weekday]
    let area = areaNamer.name(for: plan.zone ?? CLLocationCoordinate2D())
    let soft = shift.confidence == .low
    let peak = plan.peakWindow

    // Weather demand boost across the working day.
    let boost = weather.today?.hours.filter { (10...23).contains($0.hour) && $0.boostsDemand } ?? []
    let wet = boost.contains(where: \.isWet)

    let near = area.map { " near \($0)" } ?? ""

    // 1. Big night: bad weather on one of your strong days.
    if !boost.isEmpty, strongDay, let peak {
      let cond = wet ? "Wet" : "Cold"
      return ("flame.fill", OkkleColor.brand,
              plan.isToday ? "Tonight could be a big one" : "\(dayName) could be a big one",
              "\(cond) on one of your strong days — \(peak.label)\(near) tends to pay best.")
    }

    if plan.isToday, peak != nil {
      let hour = Calendar.current.component(.hour, from: Date())
      // 2. In a busy window right now.
      if let current = plan.driveWindows.first(where: { $0.startHour <= hour && hour <= $0.endHour }) {
        return ("bolt.fill", OkkleColor.brand,
                "Good time to be out",
                area.map { "Busy till \(nativeHourLabel(current.endHour + 1))\(soft ? "" : " around \($0)")." } ?? "Busy till \(nativeHourLabel(current.endHour + 1)).")
      }
      // 3. A window still ahead today.
      if let next = plan.driveWindows.first(where: { $0.startHour > hour }) {
        let boostNote = boost.isEmpty ? "" : (wet ? " Rain should help." : " Cold should help.")
        return ("figure.walk.arrival", OkkleColor.brand,
                "Great to be out for \(nativeHourLabel(next.startHour))",
                "\(next.label)\(near) \(soft ? "looks like" : "is usually") your strongest.\(boostNote)")
      }
      // 4. Peaks have passed.
      return ("moon.stars.fill", OkkleColor.muted,
              "Peaks are behind you",
              "Quieter from here — a good point to call it.")
    }

    // 5. Planning ahead for the next working day.
    if let peak {
      return ("calendar", OkkleColor.brand,
              "\(dayName) looks best from \(nativeHourLabel(peak.startHour))",
              "\(peak.label)\(near) \(soft ? "looks" : "is usually") strongest.")
    }
    return ("hourglass", OkkleColor.muted,
            "Still learning \(dayName)s",
            "A couple more shifts and the timing sharpens up.")
  }

}

/// A slim hour-by-hour intensity strip (9am–11pm) so "when exactly" is visible.
/// Tiny "quiet → busy" key so the heat colours on the graph read clearly and
/// aren't mistaken for the ranked-area badges.
struct NativeBusyLegend: View {
  var body: some View {
    HStack(spacing: 5) {
      Text("Quiet")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
      Capsule()
        .fill(LinearGradient(colors: [nativeHeatColor(0), nativeHeatColor(0.5), nativeHeatColor(1)],
                             startPoint: .leading, endPoint: .trailing))
        .frame(width: 30, height: 5)
      Text("Busy")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(OkkleColor.muted)
    }
  }
}

struct NativeHourStrip: View {
  let hourCounts: [Int]
  private let hours = Array(9...23)

  var body: some View {
    let peak = max(1, hourCounts.max() ?? 1)
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .bottom, spacing: 3) {
        ForEach(hours, id: \.self) { h in
          let value = h < hourCounts.count ? hourCounts[h] : 0
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(value == 0 ? OkkleColor.muted.opacity(0.15) : nativeHeatColor(Double(value) / Double(peak)))
            .frame(maxWidth: .infinity)
            .frame(height: max(4, CGFloat(value) / CGFloat(peak) * 32))
        }
      }
      .frame(height: 32, alignment: .bottom)
      HStack(spacing: 0) {
        ForEach([9, 12, 15, 18, 21], id: \.self) { h in
          Text(nativeHourLabel(h))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }
}

/// A ranked, real (logged, not modelled) breakdown of this period's earnings
/// by platform — a cross-platform view no single delivery app can offer.
struct NativePlatformShareList: View {
  let shares: [NativePlatformShare]

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
        HStack(spacing: 12) {
          Image(systemName: nativePlatformSymbol(share.platform))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(OkkleColor.brand)
            .frame(width: 24)
          Text(share.platform)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(OkkleColor.ink)
          Spacer(minLength: 8)
          if let delta = share.deltaPct {
            Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(delta > 0 ? OkkleColor.brand : OkkleColor.muted)
          }
          Text("\(share.sharePct)%")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(OkkleColor.ink)
        }
        .padding(.vertical, 10)
        if index < shares.count - 1 { Divider() }
      }
    }
  }
}

// MARK: - Weekly panel

struct NativeWeeklyInsightPanel: View {
  let shift: NativeShiftInsights
  @ObservedObject private var areaNamer = NativeAreaNamer.shared
  @State private var selectedWeekday: Int?
  private var todayWeekday: Int { Calendar.current.component(.weekday, from: Date()) - 1 }

  private var orderedWeekdayStats: [NativeWeekdayStat] {
    [1, 2, 3, 4, 5, 6, 0].compactMap { wd in shift.weekdayStats.first { $0.weekday == wd } }
  }

  /// Which day the breakdown reflects on: your tap, else today (if you worked
  /// it), else your busiest day.
  private var activeWeekday: Int {
    if let selectedWeekday { return selectedWeekday }
    if (shift.weekdayStats.first { $0.weekday == todayWeekday }?.count ?? 0) > 0 { return todayWeekday }
    return shift.weekdayDetails.first?.weekday ?? todayWeekday
  }

  /// A calm reflection on one day: how big it was, when it peaked, where.
  private var dayBreakdown: some View {
    let wd = activeWeekday
    let name = Calendar.current.weekdaySymbols[wd]
    let stat = shift.weekdayStats.first { $0.weekday == wd }
    let detail = shift.weekdayDetails.first { $0.weekday == wd }
    let area = detail?.coordinate.flatMap { areaNamer.name(for: $0) }

    let reliability = shift.weekdayReliability[wd]

    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(name)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        if let reliability {
          Text(reliability == .reliable ? "Reliable" : "Hit or miss")
            .font(.system(size: 10, weight: .heavy)).tracking(0.3)
            .foregroundStyle(reliability == .reliable ? OkkleColor.brand : OkkleColor.amber)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((reliability == .reliable ? OkkleColor.brand : OkkleColor.amber).opacity(0.14), in: Capsule())
        }
        Spacer()
        if let stat, stat.count > 0 {
          Text("\(stat.sharePct)% of your week")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
        }
      }
      if let detail {
        breakdownRow("clock.fill", "Best window", detail.band.timeRange)
        if let area {
          breakdownRow("mappin.circle.fill", "Busiest area", area)
        }
        breakdownRow("shippingbox.fill", "Deliveries", "about \(detail.count)")
      } else {
        Text("You don't usually work \(name)s — nothing tracked yet.")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func breakdownRow(_ symbol: String, _ label: String, _ value: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(OkkleColor.brand)
        .frame(width: 20)
      Text(label)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
      Spacer(minLength: 8)
      Text(value)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(OkkleColor.ink)
    }
  }

  /// The busiest patch and when it peaks — so the advice can name a real place
  /// and time instead of a generic "wait nearer a pick-up zone".
  private var topSpot: (area: String, time: String)? {
    guard let zone = nativeTopZones(shift.zones, near: nil, limit: 1).first,
          let area = areaNamer.name(for: zone.coordinate),
          let time = zone.timeLabel else { return nil }
    return (area, time)
  }

  /// One specific, actionable line — grounded in the driver's own busiest area
  /// and time — that replaces the vague generic warning where we can.
  private var specificAdvice: (symbol: String, color: Color, text: String)? {
    if shift.deadMilePct >= 25, let spot = topSpot {
      return ("exclamationmark.triangle.fill", OkkleColor.amber,
              "You cover a lot of empty miles between orders. Sit tight around \(spot.area) at \(spot.time) — that's where most of your pickups start.")
    }
    if let spot = topSpot {
      return ("mappin.and.ellipse", OkkleColor.brand,
              "Your strongest patch is \(spot.area) at \(spot.time) — base yourself there and let the orders come to you.")
    }
    if let warning = shift.warning {
      return ("exclamationmark.triangle.fill", OkkleColor.amber, warning)
    }
    return nil
  }

  /// Surfaces the self-correcting confidence loop — whether "your peak" has
  /// actually been paying off — so the check that runs silently in the
  /// background isn't invisible to the driver.
  private var peakHitRateLine: (symbol: String, color: Color, text: String)? {
    guard let rate = shift.peakHitRate else { return nil }
    if rate >= 0.55 {
      return ("checkmark.seal.fill", OkkleColor.brand, "Your peak-day calls have been paying off lately.")
    }
    return ("arrow.triangle.2.circlepath", OkkleColor.muted, "Recent peak days haven't stood out much — we're adjusting.")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Card 1 — a reflection on how your week actually went.
      NativeAiCard {
        VStack(alignment: .leading, spacing: 18) {
          section("BUSIEST DAYS") {
            let maxShare = max(1, shift.weekdayStats.map(\.sharePct).max() ?? 1)
            HStack(alignment: .bottom, spacing: 8) {
              ForEach(orderedWeekdayStats) { stat in
                let selected = stat.weekday == activeWeekday
                VStack(spacing: 6) {
                  Text(stat.count > 0 ? "\(stat.sharePct)%" : "")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(selected ? OkkleColor.ink : OkkleColor.muted)
                  Capsule()
                    .fill(stat.count == 0 ? OkkleColor.muted.opacity(0.18) : nativeHeatColor(Double(stat.sharePct) / Double(maxShare)))
                    .frame(width: 12, height: max(5, CGFloat(stat.sharePct) / CGFloat(maxShare) * 60))
                  Text(stat.symbol)
                    .font(.system(size: 12, weight: selected ? .heavy : .semibold))
                    .foregroundStyle(selected ? OkkleColor.ink : OkkleColor.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? OkkleColor.muted.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                  withAnimation(.easeInOut(duration: 0.15)) { selectedWeekday = stat.weekday }
                }
              }
            }
            .frame(height: 100, alignment: .bottom)
          }

          Divider()
          dayBreakdown
          Divider()
          statsStrip

          // Surfaces the self-correcting confidence loop — only appears once
          // there's genuinely enough evidence, so a newer account sees nothing.
          if let hitRate = peakHitRateLine {
            Divider()
            insightLine(symbol: hitRate.symbol, color: hitRate.color, text: hitRate.text)
          }
        }
      }

      // Card 3 — a suggestion, clearly set apart as advice (not a stat).
      if let advice = specificAdvice {
        NativeAiCard {
          section("SUGGESTION") {
            insightLine(symbol: advice.symbol, color: advice.color, text: advice.text)
          }
        }
      }

      // Card 4 — real, logged platform ranking. Only worth showing once
      // there's an actual mix — a single platform isn't a "ranking".
      if shift.platformShares.count >= 2 {
        NativeAiCard {
          section("PLATFORM MIX", subtitle: "Share of your logged earnings this period, by app.") {
            NativePlatformShareList(shares: shift.platformShares)
          }
        }
      }

      // Card 5 — your top areas, with how much of your work each one carries.
      NativeAiCard {
        section("YOUR TOP AREAS", subtitle: "Bar shows how busy each area is compared to your #1 spot.") {
          NativeTopAreasList(zones: shift.zones, limit: 4, showShareBar: true)
        }
      }
    }
  }

  private func section<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12, weight: .heavy)).tracking(0.5)
          .foregroundStyle(OkkleColor.muted)
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OkkleColor.muted.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      content()
    }
  }

  // Your fortnight in two numbers — rate only when the passive signal is solid.
  private var statsStrip: some View {
    HStack(spacing: 0) {
      if let band = shift.perHourBand {
        stat("Est. rate", "\(band)/hr")
        Divider().frame(height: 30)
      }
      stat("Unpaid miles", "\(shift.deadMilePct)%")
    }
    .padding(.vertical, 4)
  }

  private func stat(_ title: String, _ value: String) -> some View {
    VStack(spacing: 3) {
      Text(value)
        .font(.system(size: 19, weight: .bold, design: .rounded))
        .foregroundStyle(OkkleColor.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(OkkleColor.muted)
    }
    .frame(maxWidth: .infinity)
  }

  private func insightLine(symbol: String, color: Color, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(color)
        .padding(.top, 1)
      Text(text)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(OkkleColor.ink)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }
}

struct NativeInsightsView: View {
  @EnvironmentObject private var store: OkkleStore
  @ObservedObject private var autoTrack = NativeAutoTrackEngine.shared
  private var shift: NativeShiftInsights {
    NativeShiftInsights.build(visits: autoTrack.visits, store: store)
  }

  var body: some View {
    NativeScreen(title: "Insights", collapsedTitle: "Insights",
                 subtitle: "From your trips: when to head out and where to go. Sharper the more you drive.") {
      NativeShiftPatternsCard(
        shift: shift,
        visits: autoTrack.visits,
        trips: store.trips,
        autoTrackTrips: Binding(
          get: { store.settings.autoTrackTrips },
          set: { value in
            withAnimation(nativeInsightPromptAnimation) {
              store.settings.autoTrackTrips = value
            }
          }
        )
      )

      // These cards are one-time set-up prompts: they only appear while
      // the feature is off. Once you turn one on it disappears here — the on/off
      // switch then lives in Settings.
      if !store.settings.siriTripTrackingEnabled {
        NativeSiriTripTrackingPrompt()
          .transition(.nativeInsightSetupCard)
      }

      if !store.settings.loggingReminder {
        NativeAiCard(banner: "REMINDERS") {
          VStack(alignment: .leading, spacing: 16) {
            Text("Keep your records fresh")
              .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Get a gentle nudge to log your miles and pay so nothing slips through the week.")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(OkkleColor.muted)
            Toggle("Logging reminder", isOn: Binding(
              get: { store.settings.loggingReminder },
              set: { value in
                withAnimation(nativeInsightPromptAnimation) {
                  store.settings.loggingReminder = value
                }
              }
            ))
            .font(.system(size: 17, weight: .bold))
            .tint(OkkleColor.brand)
          }
        }
        .transition(.nativeInsightSetupCard)
      }

      if !store.settings.taxDeadlineReminders {
        NativeKeyTaxDatesPanel()
          .transition(.nativeInsightSetupCard)
      }

      if store.history.isEmpty {
        NativeEmptyState(symbol: "sparkles", title: "Insights will grow with your data", message: "Track trips and log pay to unlock best zones, hours, platform mix and tax-aware suggestions.")
      }
    }
    .animation(nativeInsightPromptAnimation, value: store.settings.autoTrackTrips)
    .animation(nativeInsightPromptAnimation, value: store.settings.siriTripTrackingEnabled)
    .animation(nativeInsightPromptAnimation, value: store.settings.loggingReminder)
    .animation(nativeInsightPromptAnimation, value: store.settings.taxDeadlineReminders)
  }
}

private struct NativeInsightSetupCardTransition: ViewModifier {
  let progress: CGFloat

  func body(content: Content) -> some View {
    content
      .opacity(1 - progress)
      .scaleEffect(1 - (0.12 * progress), anchor: .top)
      .offset(y: -24 * progress)
      .rotationEffect(.degrees(-2.5 * progress), anchor: .topTrailing)
      .blur(radius: 8 * progress)
  }
}

private extension AnyTransition {
  static var nativeInsightSetupCard: AnyTransition {
    .asymmetric(
      insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .move(edge: .top)),
      removal: .modifier(
        active: NativeInsightSetupCardTransition(progress: 1),
        identity: NativeInsightSetupCardTransition(progress: 0)
      )
    )
  }
}

struct NativeSiriTripTrackingPrompt: View {
  @EnvironmentObject private var store: OkkleStore

  var body: some View {
    NativeAiCard(banner: "SIRI") {
      VStack(alignment: .leading, spacing: 16) {
        Text("Start trips by voice")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Let Siri and Shortcuts start or resume trip tracking with your default vehicle.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
        Toggle("Siri trip tracking", isOn: Binding(
          get: { store.settings.siriTripTrackingEnabled },
          set: { value in
            withAnimation(nativeInsightPromptAnimation) {
              store.settings.siriTripTrackingEnabled = value
            }
          }
        ))
        .font(.system(size: 17, weight: .bold))
        .tint(OkkleColor.brand)
      }
    }
  }
}

struct NativeTaxDeadline: Identifiable {
  let title: String
  let month: Int
  let day: Int
  let note: String

  var id: String { title }

  func nextOccurrence(from reference: Date = Date()) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: reference)
    let year = calendar.component(.year, from: reference)
    var components = DateComponents(year: year, month: month, day: day, hour: 9, minute: 0)
    var date = calendar.date(from: components) ?? reference
    if date < today {
      components.year = year + 1
      date = calendar.date(from: components) ?? reference
    }
    return date
  }
}

let nativeTaxDeadlines = [
  NativeTaxDeadline(title: "Register for Self Assessment", month: 10, day: 5, note: "Only if this was your first year self-employed."),
  NativeTaxDeadline(title: "File your return & pay your tax", month: 1, day: 31, note: "Online Self Assessment deadline for the previous tax year."),
  NativeTaxDeadline(title: "Second payment on account", month: 7, day: 31, note: "Only if HMRC asked you for payments on account.")
]

func nativeDaysUntil(_ date: Date) -> Int {
  let calendar = Calendar.current
  let today = calendar.startOfDay(for: Date())
  let target = calendar.startOfDay(for: date)
  return calendar.dateComponents([.day], from: today, to: target).day ?? 0
}

func nativeTaxDateLabel(_ date: Date) -> String {
  date.formatted(.dateTime.day().month(.wide).year())
}

@MainActor
func nativeAddDeadlineToCalendar(_ deadline: NativeTaxDeadline) async -> Bool {
  let eventStore = EKEventStore()
  do {
    let granted: Bool
    if #available(iOS 17.0, *) {
      granted = try await eventStore.requestFullAccessToEvents()
    } else {
      granted = try await withCheckedThrowingContinuation { continuation in
        eventStore.requestAccess(to: .event) { granted, error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: granted)
          }
        }
      }
    }
    guard granted, let calendar = eventStore.defaultCalendarForNewEvents else { return false }

    let start = deadline.nextOccurrence()
    let end = Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start.addingTimeInterval(1800)
    let event = EKEvent(eventStore: eventStore)
    event.calendar = calendar
    event.title = "HMRC: \(deadline.title)"
    event.startDate = start
    event.endDate = end
    event.notes = deadline.note
    event.addAlarm(EKAlarm(relativeOffset: -60 * 60 * 24 * 7))
    try eventStore.save(event, span: .thisEvent)
    return true
  } catch {
    return false
  }
}

struct NativeKeyTaxDatesPanel: View {
  @EnvironmentObject private var store: OkkleStore
  @State private var showSheet = false

  var body: some View {
    NativeAiCard(banner: "KEY TAX DATES") {
      VStack(alignment: .leading, spacing: 16) {
        Text("Keep HMRC deadlines close")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(OkkleColor.ink)
        Text("Review Self Assessment dates and add reminders to your calendar.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
        Toggle("Tax deadline reminders", isOn: Binding(
          get: { store.settings.taxDeadlineReminders },
          set: { value in
            withAnimation(nativeInsightPromptAnimation) {
              store.settings.taxDeadlineReminders = value
            }
          }
        ))
        .font(.system(size: 17, weight: .bold))
        .tint(OkkleColor.brand)
        Button {
          showSheet = true
        } label: {
          HStack {
            Text("View dates")
              .font(.system(size: 16, weight: .bold))
            Spacer()
            Image(systemName: "chevron.up")
              .font(.system(size: 15, weight: .bold))
          }
          .foregroundStyle(Color.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 14)
          .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .sheet(isPresented: $showSheet) {
      NativeKeyTaxDatesSheet()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }
}

struct NativeKeyTaxDatesSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var alertMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Add these dates to Calendar with a reminder one week before.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)

          NativeGlassCard {
            VStack(spacing: 0) {
              ForEach(nativeTaxDeadlines) { deadline in
                NativeTaxDeadlineRow(deadline: deadline) { message in
                  alertMessage = message
                }
                if deadline.id != nativeTaxDeadlines.last?.id {
                  Divider().padding(.leading, 0)
                }
              }
            }
          }

          Button {
            Task {
              var added = 0
              for deadline in nativeTaxDeadlines {
                if await nativeAddDeadlineToCalendar(deadline) {
                  added += 1
                }
              }
              alertMessage = added == nativeTaxDeadlines.count
                ? "All key tax dates were added to your calendar."
                : "Added \(added) of \(nativeTaxDeadlines.count) dates. Please allow calendar access and try again for the rest."
            }
          } label: {
            Label("Add all dates", systemImage: "calendar.badge.plus")
              .font(.system(size: 16, weight: .bold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 15)
              .foregroundStyle(Color.white)
              .background(OkkleColor.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
          .buttonStyle(.plain)

          Text("Keep your records for at least 5 years after the 31 January deadline. MTD for Income Tax adds quarterly updates once your income passes the threshold.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(OkkleColor.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
      }
      .background(NativeBackground())
      .navigationTitle("Key tax dates")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
      .alert("Calendar", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(alertMessage ?? "")
      }
    }
  }
}

struct NativeTaxDeadlineRow: View {
  let deadline: NativeTaxDeadline
  let onResult: (String) -> Void
  @State private var busy = false

  var body: some View {
    let next = deadline.nextOccurrence()
    let days = nativeDaysUntil(next)
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(deadline.title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(OkkleColor.ink)
        Text("\(nativeTaxDateLabel(next)) - \(daysLabel(days))")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(OkkleColor.brandDark)
        Text(deadline.note)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(OkkleColor.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button {
        busy = true
        Task {
          let ok = await nativeAddDeadlineToCalendar(deadline)
          busy = false
          onResult(ok
            ? "\(deadline.title) was added to your calendar with a reminder one week before."
            : "Could not add \(deadline.title). Please allow calendar access and try again.")
        }
      } label: {
        Label(busy ? "Adding" : "Add", systemImage: "calendar.badge.plus")
          .font(.system(size: 13, weight: .bold))
          .labelStyle(.titleAndIcon)
          .foregroundStyle(OkkleColor.brandDark)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .background(OkkleColor.brand.opacity(0.13), in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(busy)
    }
    .padding(.vertical, 13)
  }

  private func daysLabel(_ days: Int) -> String {
    if days == 0 { return "today" }
    if days == 1 { return "tomorrow" }
    return "in \(days) days"
  }
}

// MARK: - Analysis

/// One weekday + time-of-day bucket, ranked by how many deliveries land in it.
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
  let weight: Double   // 0 (quiet) ... 1 (your busiest zone)
  var count: Int = 0   // raw deliveries in this cluster
  var peakHour: Int? = nil   // the hour this area is busiest for you

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
  let peakHitRate: Double?                     // how often "your peak" has actually paid off
  let weekdayReliability: [Int: NativeDayReliability]   // per-weekday, week-to-week consistency
  let platformShares: [NativePlatformShare]             // ranked, only populated with 2+ platforms logged

  var hasData: Bool { deliveries > 0 }
  var totalMiles: Double { paidMiles + deadMiles }
  var deadMilePct: Int {
    guard totalMiles > 0 else { return 0 }
    return Int((deadMiles / totalMiles * 100).rounded())
  }

  /// Overall evidence level: enough deliveries across enough distinct days,
  /// *and* those days actually look alike. Sample size alone can be
  /// misleading — five visits that all landed near the same volume is a
  /// genuinely repeatable pattern; five visits where one outlier day did most
  /// of the work is really a single fluke wearing a big-sample-size costume.
  /// The day-to-day spread (coefficient of variation across active weekdays)
  /// catches that and caps confidence accordingly, even when the raw totals
  /// look strong.
  var confidence: NativeConfidence {
    var level: NativeConfidence
    if deliveries >= 20 && activeDays >= 6 { level = .high }
    else if deliveries >= 8 && activeDays >= 3 { level = .medium }
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

  static let empty = NativeShiftInsights(
    deliveries: 0, activeHours: 0, paidMiles: 0, deadMiles: 0,
    bestWindow: nil, perHour: nil, windows: [], quietWindow: nil, zones: [],
    weekdayStats: [], weekdayDetails: [], todayPlan: nil, lastShift: nil,
    activeDays: 0, peakHitRate: nil, weekdayReliability: [:],
    platformShares: []
  )

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
    for k in 1..<sorted.count {
      let prev = sorted[k - 1], cur = sorted[k]
      let gap = cur.arrival.timeIntervalSince(prev.departure)
      if gap < shiftGap {
        totalMeters += routeMeters(from: prev.departure, to: cur.arrival, trips: store.trips)
          ?? cur.location.distance(from: prev.location)
        activeSeconds += max(0, gap) + prev.dwell
      }
    }
    activeSeconds += sorted.last?.dwell ?? 0

    // Deliveries + paid distance: a pick-up drives to the next drop-off.
    var deliveries = 0
    var paidMeters = 0.0
    var deliveryHits: [(weekday: Int, band: NativeTimeFilter, hour: Int, coordinate: CLLocationCoordinate2D, date: Date)] = []
    var index = 0
    while index < sorted.count {
      if sorted[index].kind == .pickup,
         let dropIndex = (index + 1..<sorted.count).first(where: { sorted[$0].kind == .dropoff }) {
        deliveries += 1
        // Paid = the active delivery leg (restaurant → customer). Everything
        // else (repositioning back out to the next pick-up, idle wandering) is
        // unpaid mileage. Real route distance when a recorded trip covers this
        // leg, otherwise a straight-line estimate.
        paidMeters += routeMeters(from: sorted[index].departure, to: sorted[dropIndex].arrival, trips: store.trips)
          ?? sorted[dropIndex].location.distance(from: sorted[index].location)
        let date = sorted[dropIndex].arrival
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let hour = Calendar.current.component(.hour, from: date)
        let band = NativeTimeFilter.allCases.first { $0 != .all && $0.includes(date) } ?? .afternoon
        deliveryHits.append((weekday, band, hour, sorted[index].coordinate, date))
        index = dropIndex + 1
      } else {
        index += 1
      }
    }

    let paidMiles = paidMeters / 1609.34 * roadFactor
    let totalMiles = max(totalMeters / 1609.34 * roadFactor, paidMiles)
    let deadMiles = max(0, totalMiles - paidMiles)
    let activeHours = activeSeconds / 3600

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
    // is already free of excluded places, since `sorted` was filtered above.
    var cells: [String: (coordinate: CLLocationCoordinate2D, count: Int, hours: [Int: Int])] = [:]
    let cellSize = 0.006
    for hit in deliveryHits {
      let key = "\(Int((hit.coordinate.latitude / cellSize).rounded())),\(Int((hit.coordinate.longitude / cellSize).rounded()))"
      var cell = cells[key] ?? (hit.coordinate, 0, [:])
      cell.count += 1
      cell.hours[hit.hour, default: 0] += 1
      cells[key] = cell
    }
    let maxCount = cells.values.map(\.count).max() ?? 1
    let zones = cells.values.map { cell -> NativeZonePoint in
      let peak = cell.hours.max { $0.value < $1.value }?.key
      return NativeZonePoint(coordinate: cell.coordinate, weight: Double(cell.count) / Double(maxCount), count: cell.count, peakHour: peak)
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
        return NativeWeekdayDetail(weekday: wd, band: band, count: weekdayCounts[wd] ?? 0, coordinate: zone)
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
      peakHitRate: NativeOutcomeTracker.shared.peakHitRate,
      weekdayReliability: weekdayReliability,
      platformShares: platformShares
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

  /// Real driven distance (metres) between two timestamps, summed from the
  /// actual recorded route points of any trip covering that window — not a
  /// straight line between the two stops. Falls back to nil when no trip
  /// data covers the window (older data, or a stop that wasn't part of a
  /// recorded shift/trip) so callers can fall back to a straight-line
  /// estimate instead.
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
      guard inWindow.count > 1 else { continue }
      sawSegment = true
      for i in 1..<inWindow.count {
        let a = CLLocation(latitude: inWindow[i - 1].latitude, longitude: inWindow[i - 1].longitude)
        let b = CLLocation(latitude: inWindow[i].latitude, longitude: inWindow[i].longitude)
        total += b.distance(from: a)
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

typealias NativeDeliveryHit = (weekday: Int, band: NativeTimeFilter, hour: Int, coordinate: CLLocationCoordinate2D, date: Date)

/// The busiest time-band and roughly-where for one weekday.
func bestBandAndZone(for weekday: Int, deliveryHits: [NativeDeliveryHit], cellSize: Double) -> (band: NativeTimeFilter, zone: CLLocationCoordinate2D?) {
  var bandCounts: [NativeTimeFilter: Int] = [:]
  var cells: [String: (coordinate: CLLocationCoordinate2D, count: Int)] = [:]
  for hit in deliveryHits where hit.weekday == weekday {
    bandCounts[hit.band, default: 0] += 1
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
